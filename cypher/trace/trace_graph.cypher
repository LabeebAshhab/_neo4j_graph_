// CARD - "Money trail" (report type: Graph, layout tree-top-down)
//
// Same rule and parameters as trace_table.cypher - read that file's
// header for the full explanation. This card draws the result as one
// vertical chain, read top to bottom:
//
//   From <sender>                      who paid the credit in
//     | credited 500 tk
//   CREDIT 500 tk - P2P - 2024-04-07 17:59
//     | uses 200 tk - left 300 tk
//   #1 2024-04-07 19:53 - P2P 200 tk
//     | uses 250 tk - left 50 tk
//   #2 ...
//     | uses 50 tk - left 0 tk
//   #3 2024-04-08 10:30 - CASH OUT 100 tk
//     |
//   TERMINATED 2024-04-08 10:30:47     the debit that used the last paisa
//
// READABILITY. A large credit can take hundreds of debits to use up. The
// chain always shows the first 6 and the last 6 steps - the last one being
// the terminating debit - and folds everything in between into one
// "... n more debits" node carrying their total. The step table below the
// graph lists every step.
//
// Nothing here is stored: the chain is built from APOC virtual nodes on
// each run, so it never touches the database.
WITH coalesce($neodash_trace_credit, '') AS ck,
     coalesce($neodash_trace_mode, 'credit_first') AS mode
MATCH (c:Canon {row_key: ck})
WHERE c.stmt_acc = coalesce($neodash_trace_acc, '')   // switching customer clears the trail
WITH c, mode,
     toInteger(round(c.amount * 1000000)) AS credit_u,
     toInteger(round((c.balance_after - c.amount) * 1000000)) AS prior_u
WITH c, mode, credit_u,
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
WITH c, mode, credit_u, ds, cut,
     [i IN range(0, CASE WHEN cut >= 0 THEN cut ELSE size(ds) - 1 END) |
        {d: ds[i], n: i,
         used: (CASE WHEN cum[i] < target_u THEN cum[i] ELSE target_u END)
             - (CASE WHEN i > 0 AND cum[i - 1] > skip_u THEN cum[i - 1] ELSE skip_u END),
         left: target_u - (CASE WHEN cum[i] < target_u THEN cum[i] ELSE target_u END)}
     ] AS all_steps
WITH c, mode, credit_u, ds, cut,
     [s IN all_steps WHERE s.used > 0] AS steps
WITH c, mode, credit_u, ds, cut, steps,
     reduce(u = 0, s IN steps | u + s.used) AS used_total_u
// Fold the middle of a long chain into one node.
WITH c, mode, credit_u, ds, cut, steps, used_total_u,
     CASE WHEN size(steps) <= 13
          THEN [k IN range(0, size(steps) - 1) | {kind: 'step', k: k, s: steps[k]}]
          ELSE [k IN range(0, 5) | {kind: 'step', k: k, s: steps[k]}]
             + [{kind: 'gap', k: 6, s: null,
                 cnt: size(steps) - 12,
                 amt: reduce(u = 0, s IN steps[6 .. size(steps) - 6] | u + s.used),
                 left: steps[size(steps) - 7].left}]
             + [k IN range(size(steps) - 6, size(steps) - 1) | {kind: 'step', k: k, s: steps[k]}]
     END AS shown

// --- the nodes ------------------------------------------------------
CALL apoc.create.vNode(['TraceSource'], {
  name: 'From ' + coalesce(c.with_acc, '?'),
  account: c.with_acc
}) YIELD node AS src
CALL apoc.create.vNode(['TraceCredit'], {
  name: 'CREDIT ' + apoc.number.format(c.amount, '#,##0.######') + ' tk  -  ' + c.txn_type +
        '  -  ' + substring(c.txn_date_time, 0, 16),
  customer: c.stmt_acc,
  amount: c.amount,
  txn_type: c.txn_type,
  txn_date_time: c.txn_date_time,
  txn_id: c.txn_id,
  balance_after: c.balance_after,
  mode: mode
}) YIELD node AS cr
CALL apoc.create.vRelationship(src, 'CREDITED', {
  name: 'credited ' + apoc.number.format(c.amount, '#,##0.######') + ' tk',
  amount: c.amount
}, cr) YIELD rel AS r0

CALL {
  WITH shown
  UNWIND shown AS x
  CALL apoc.create.vNode(
    [CASE x.kind WHEN 'gap' THEN 'TraceGap' ELSE 'TraceStep' END],
    CASE x.kind
      WHEN 'gap' THEN {
        name: '... ' + toString(x.cnt) + ' more debits  -  ' +
              apoc.number.format(x.amt / 1000000.0, '#,##0.######') + ' tk from this credit',
        debits: x.cnt,
        used_from_credit: x.amt / 1000000.0,
        credit_left_after: x.left / 1000000.0
      }
      ELSE {
        name: '#' + toString(x.k + 1) + '  ' + substring(x.s.d.txn_date_time, 0, 16) + '  -  ' +
              x.s.d.txn_type + '  ' + apoc.number.format(x.s.d.amount, '#,##0.######') + ' tk',
        step: x.k + 1,
        txn_date_time: x.s.d.txn_date_time,
        txn_type: x.s.d.txn_type,
        to_account: x.s.d.with_acc,
        debit_amount: x.s.d.amount,
        used_from_credit: x.s.used / 1000000.0,
        credit_left_after: x.s.left / 1000000.0,
        balance_after: x.s.d.balance_after,
        txn_id: x.s.d.txn_id
      }
    END
  ) YIELD node
  RETURN collect({node: node, x: x}) AS chain
}

// --- the end of the trail -------------------------------------------
WITH c, cr, src, r0, ds, cut, steps, chain, credit_u, used_total_u,
     CASE WHEN cut >= 0 THEN steps[size(steps) - 1].d ELSE null END AS term
CALL apoc.create.vNode(['TraceEnd'], CASE
  WHEN term IS NOT NULL THEN {
    name: 'TERMINATED  ' + term.txn_date_time + '  (step ' + toString(size(steps)) + ')',
    terminated: true,
    at: term.txn_date_time,
    by_txn_type: term.txn_type,
    to_account: term.with_acc,
    steps: size(steps)
  }
  WHEN size(ds) >= 20000 THEN {
    name: 'NOT TERMINATED within 20,000 debits  -  ' +
          apoc.number.format((credit_u - used_total_u) / 1000000.0, '#,##0.######') + ' tk left',
    terminated: false,
    left: (credit_u - used_total_u) / 1000000.0
  }
  ELSE {
    name: 'NOT TERMINATED  -  ' +
          apoc.number.format((credit_u - used_total_u) / 1000000.0, '#,##0.######') +
          ' tk still unspent at end of data',
    terminated: false,
    left: (credit_u - used_total_u) / 1000000.0
  }
END) YIELD node AS endn

// --- the edges: credit -> step 1 -> step 2 -> ... -> end -------------
WITH src, cr, r0, endn, chain,
     [cr] + [x IN chain | x.node] AS froms,
     [x IN chain | x] AS tos
CALL {
  WITH froms, tos
  UNWIND range(0, size(tos) - 1) AS i
  WITH froms[i] AS a, tos[i] AS t
  CALL apoc.create.vRelationship(a, 'SPENT', {
    name: CASE t.x.kind
            WHEN 'gap' THEN 'uses ' + apoc.number.format(t.x.amt / 1000000.0, '#,##0.######') +
                            ' tk  -  left ' + apoc.number.format(t.x.left / 1000000.0, '#,##0.######') + ' tk'
            ELSE 'uses ' + apoc.number.format(t.x.s.used / 1000000.0, '#,##0.######') +
                 ' tk  -  left ' + apoc.number.format(t.x.s.left / 1000000.0, '#,##0.######') + ' tk'
          END
  }, t.node) YIELD rel
  RETURN collect(rel) AS rels
}
WITH src, cr, r0, endn, rels, [x IN chain | x.node] AS step_nodes,
     CASE WHEN size(chain) = 0 THEN cr ELSE chain[size(chain) - 1].node END AS last
CALL apoc.create.vRelationship(last, 'ENDS', {
  name: CASE WHEN endn.terminated THEN '0 tk left' ELSE 'trail ends' END
}, endn) YIELD rel AS rEnd
// every node must be returned, not only the relationships between them -
// NeoDash cannot draw a relationship whose end node is missing
RETURN src, cr, step_nodes, endn, r0, rels, rEnd
