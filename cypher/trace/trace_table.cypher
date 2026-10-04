// CARD - "Money trail - step by step" (report type: Table)
//
// Parameters (set by clicking in the other cards on the Money Trail page):
//   $neodash_trace_credit  row_key of the credit being traced
//   $neodash_trace_mode    'credit_first' (default) or 'fifo'
//
// THE RULE. Take one credit, e.g. 500 tk into a customer's account. Walk
// that customer's debits forward in date-time order - P2P, TOP UP, CASH
// OUT, PAYMENT, service fees, everything that left the account - and
// charge each one against the credit until nothing is left. The debit
// that takes the balance of the credit to zero is where the amount
// TERMINATES.
//
//   credit_first  every debit after the credit is paid out of THIS credit
//                 first. What you asked for: "after the credited amount,
//                 where did the user debit it".
//   fifo          money already in the account before the credit is spent
//                 first (first in, first out); this credit starts being
//                 used only once that older balance is gone.
//
// EXACTNESS. Amounts are converted to integer micro-taka (x 1,000,000)
// before any adding up, so there is no floating-point drift: the trail
// does not stop while even 0.0001 tk of the credit is left, and stops on
// exactly the debit that uses the last of it.
//
// Reads :Canon rows only (see cypher/05_build_trace_layer.cypher) so the
// copies duplicated in the source extract are not counted 414 times.
WITH coalesce($neodash_trace_credit, '') AS ck,
     coalesce($neodash_trace_mode, 'credit_first') AS mode,
     20000 AS max_debits   // keep in step with the LIMIT below
MATCH (c:Canon {row_key: ck})
WHERE c.stmt_acc = coalesce($neodash_trace_acc, '')   // switching customer clears the trail
WITH c, mode, max_debits,
     toInteger(round(c.amount * 1000000)) AS credit_u,
     toInteger(round((c.balance_after - c.amount) * 1000000)) AS prior_u
WITH c, mode, max_debits, credit_u,
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
WITH c, mode, credit_u, skip_u, ds, skip_u + credit_u AS target_u,
     apoc.coll.runningTotal([x IN ds | toInteger(round(x.amount * 1000000))]) AS cum
WITH c, mode, credit_u, skip_u, target_u, ds, cum,
     coalesce([i IN range(0, size(ds) - 1) WHERE cum[i] >= target_u][0], -1) AS cut
UNWIND range(0, CASE WHEN cut >= 0 THEN cut ELSE size(ds) - 1 END) AS i
WITH c, mode, credit_u, skip_u, target_u, ds, cum, cut, i,
     CASE WHEN i = 0 THEN 0 ELSE cum[i - 1] END AS before_u
WITH c, mode, credit_u, target_u, ds[i] AS d, i, cut,
     (CASE WHEN cum[i] < target_u THEN cum[i] ELSE target_u END)
       - (CASE WHEN before_u > skip_u THEN before_u ELSE skip_u END) AS used_u,
     target_u - (CASE WHEN cum[i] < target_u THEN cum[i] ELSE target_u END) AS left_u
WHERE used_u > 0
WITH c, d, i, cut, used_u, left_u
ORDER BY i
WITH c, collect({d: d, i: i, cut: cut, used: used_u, left: left_u}) AS steps
UNWIND range(0, size(steps) - 1) AS k
WITH c, steps[k] AS s, k
RETURN k + 1                                          AS STEP,
       s.d.txn_date_time                              AS TXN_DATE_TIME,
       s.d.txn_type                                   AS TXN_TYPE,
       s.d.with_acc                                   AS TXN_WITH_ACC,
       s.d.amount                                     AS DEBIT_AMT,
       s.used / 1000000.0                             AS FROM_THIS_CREDIT,
       s.left / 1000000.0                             AS CREDIT_LEFT_AFTER,
       CASE WHEN s.i = s.cut THEN 'TERMINATED HERE' ELSE '' END AS STATUS,
       s.d.balance_after                              AS AVAILABLE_BLC_AFTER_TXN,
       s.d.txn_id                                     AS TXN_ID,
       s.d.channel                                    AS CHANNEL,
       s.d.reference                                  AS REFERENCE
ORDER BY STEP
