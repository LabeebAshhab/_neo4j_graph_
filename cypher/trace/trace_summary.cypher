// CARD - "Where did it terminate?" (report type: Table)
// One-glance answer for the credit being traced: when and on which debit
// the credited amount was used up, and how long that took. Same rule as
// trace_table.cypher.
WITH coalesce($neodash_trace_credit, '') AS ck,
     coalesce($neodash_trace_mode, 'credit_first') AS mode
OPTIONAL MATCH (c:Canon {row_key: ck})
WHERE c.stmt_acc = coalesce($neodash_trace_acc, '')
WITH c, mode
OPTIONAL CALL {   // OPTIONAL: nothing picked yet still returns the hint row
  WITH c, mode
  WITH c, mode
  WHERE c IS NOT NULL
  WITH c, mode,
       toInteger(round(c.amount * 1000000)) AS credit_u,
       toInteger(round((c.balance_after - c.amount) * 1000000)) AS prior_u
  WITH c, credit_u,
       CASE WHEN mode = 'fifo' AND prior_u > 0 THEN prior_u ELSE 0 END AS skip_u
  CALL {
    WITH c
    MATCH (d:Canon)
    WHERE d.stmt_acc = c.stmt_acc
      AND d.txn_type_d_c = 'D'
      AND d.txn_date_time >= c.txn_date_time
      AND (d.txn_date_time > c.txn_date_time OR coalesce(d.serial_no, 0) > coalesce(c.serial_no, 0))
    WITH d ORDER BY d.txn_date_time, d.serial_no
    LIMIT 20000
    RETURN collect(d) AS ds
  }
  WITH c, credit_u, skip_u, ds, skip_u + credit_u AS target_u,
       apoc.coll.runningTotal([x IN ds | toInteger(round(x.amount * 1000000))]) AS cum
  WITH c, credit_u, skip_u, ds, target_u, cum,
       coalesce([i IN range(0, size(ds) - 1) WHERE cum[i] >= target_u][0], -1) AS cut
  WITH c, credit_u, ds, cut,
       size([i IN range(0, CASE WHEN cut >= 0 THEN cut ELSE size(ds) - 1 END) WHERE cum[i] > skip_u]) AS steps,
       CASE WHEN size(ds) = 0 THEN 0
            WHEN cut >= 0 THEN credit_u
            WHEN cum[size(ds) - 1] > skip_u THEN cum[size(ds) - 1] - skip_u
            ELSE 0 END AS used_u
  WITH c, ds, cut, steps, used_u, credit_u,
       CASE WHEN cut >= 0 THEN ds[cut] ELSE null END AS t
  WITH c, ds, steps, used_u, credit_u, t,
       CASE WHEN t IS NULL THEN null
            ELSE duration.inSeconds(localdatetime(replace(c.txn_date_time, ' ', 'T')),
                                    localdatetime(replace(t.txn_date_time, ' ', 'T'))).seconds END AS secs
  RETURN [
    ['Customer',              c.stmt_acc],
    ['Credit',                apoc.number.format(c.amount, '#,##0.######') + ' tk  (' + c.txn_type + ')'],
    ['Credited at',           c.txn_date_time],
    ['Credited from',         coalesce(c.with_acc, '-')],
    ['Status',                CASE WHEN t IS NOT NULL THEN 'TERMINATED'
                                   WHEN size(ds) >= 20000 THEN 'NOT TERMINATED within 20,000 debits'
                                   ELSE 'NOT TERMINATED - still unspent at end of data' END],
    ['Terminated at',         coalesce(t.txn_date_time, '-')],
    ['Terminating debit',     CASE WHEN t IS NULL THEN '-'
                                   ELSE t.txn_type + '  ' + apoc.number.format(t.amount, '#,##0.######') +
                                        ' tk  to ' + coalesce(t.with_acc, '-') END],
    ['Debits that used it',   toString(steps)],
    ['Time to terminate',     CASE WHEN secs IS NULL THEN '-'
                                   ELSE toString(secs / 86400) + ' d ' + toString((secs % 86400) / 3600) + ' h ' +
                                        toString((secs % 3600) / 60) + ' m ' + toString(secs % 60) + ' s' END],
    ['Spent from this credit', apoc.number.format(used_u / 1000000.0, '#,##0.######') + ' tk'],
    ['Left unspent',          apoc.number.format((credit_u - used_u) / 1000000.0, '#,##0.######') + ' tk']
  ] AS rows
}
WITH mode, CASE WHEN c IS NULL
                THEN [['Status', 'Pick a customer, then click TRACE on one of their credits']]
                ELSE rows END AS rows
UNWIND rows + [['Rule', mode]] AS r
RETURN r[0] AS ITEM, r[1] AS VALUE
