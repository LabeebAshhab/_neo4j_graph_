// CARD - "By layer" (report type: Table)
// Per trail and layer, P2P only: what was sent, what of it is traced,
// the minus, and of the traced money what the people of that layer kept
// and what they passed on into the next layer.
// Follows the clicked person's trail; every trail when nothing is clicked.
WITH coalesce($neodash_lyr_focus, '') AS fk
OPTIONAL MATCH (f:LNet {key: fk})
WITH CASE WHEN f IS NULL OR f:LHeader THEN null ELSE f.tag END AS tag
MATCH (a)-[e:LFLOW]->(b:LNet)
WHERE tag IS NULL OR e.tag = tag
WITH e.tag AS t, e.layer AS L, b,
     sum(e.sent) AS sent, sum(e.amount) AS traced, sum(e.txn_count) AS txns
WITH t, L, sum(txns) AS txns, count(b) AS people, sum(sent) AS sent, sum(traced) AS traced,
     sum(b.kept) AS kept, sum(b.traced_out) AS passed_on
RETURN t AS TXN_SL_TAG, L AS LAYER, people AS PEOPLE, txns AS P2P_TXNS,
       round(sent, 2)          AS SENT,
       round(traced, 2)        AS TRACED,
       round(sent - traced, 2) AS MINUS_NOT_TRACED,
       round(kept, 2)          AS KEPT,
       round(passed_on, 2)     AS PASSED_ON
ORDER BY coalesce(toIntegerOrNull(TXN_SL_TAG), 0), TXN_SL_TAG, LAYER
