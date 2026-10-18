// CARD - "Transactions" (report type: Table)
// The P2P rows on the arrows currently drawn (same rule as
// cards/graph.cypher), with what the trace counted.
//   TRACED_AMT - the part of TXN_AMT that carries the layer-1 money
//   MINUS_AMT  - TXN_AMT - TRACED_AMT (orange in the graph)
//   LAYERED_MONEY / DIFF - the sheet's own figure, when the table has that
//                column, and TRACED_AMT - LAYERED_MONEY (0 = they agree)
WITH coalesce($neodash_lyr_focus, '') AS fk
OPTIONAL MATCH (f:LNet {key: fk})
WITH coalesce(f.chain, []) AS chain
MATCH (n:LNet)
WHERE NOT n:LHeader AND (n.parent_key IS NULL OR n.layer = 1 OR n.parent_key IN chain)
WITH collect(n.key) AS shown
MATCH (r:LyrTxn {p2p: true})
WHERE r.to_key IN shown AND r.from_key IN shown
RETURN r.tag               AS TXN_SL_TAG,
       r.layer             AS LAYER,
       r.ts_text           AS APPROVAL_DATETIME,
       r.txn_id            AS TXN_ID,
       r.from_acc          AS TXN_FROM,
       r.with_acc          AS TXN_WITH,
       r.txn_type          AS TXN_TYPE,
       r.amount            AS TXN_AMT,
       round(r.traced, 2)  AS TRACED_AMT,
       round(r.excess, 2)  AS MINUS_AMT,
       r.layered_money     AS LAYERED_MONEY,
       CASE WHEN r.layered_money IS NULL THEN null ELSE round(r.traced - r.layered_money, 2) END AS DIFF,
       r.channel           AS CHANNEL,
       r.post_blc          AS POST_BLC
ORDER BY coalesce(toIntegerOrNull(TXN_SL_TAG), 0), TXN_SL_TAG, LAYER, r.ts
