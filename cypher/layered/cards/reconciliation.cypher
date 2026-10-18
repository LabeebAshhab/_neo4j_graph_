// CARD - "Does it add up?" (report type: Table)
// Per trail: the layer-1 P2P amount, and the traced money every person
// kept after the last layer. KEPT equals START (CHECK = OK) - the
// "after 5 layers it matches the first transfer" check. The non-P2P
// rows left out of the trace are counted for reference.
MATCH (s:LSource)
WITH s.tag AS tag, collect(s.acc) AS sources, sum(s.sent) AS start
MATCH (n:LAccount {tag: tag})
WITH tag, sources, start, max(n.layer) AS layers, count(n) AS people, sum(n.kept) AS kept
CALL {
  WITH tag
  MATCH (r:LyrTxn {tag: tag, p2p: false})
  RETURN count(r) AS skipped, coalesce(sum(r.amount), 0.0) AS skipped_amt
}
RETURN tag AS TXN_SL_TAG,
       reduce(s = '', a IN sources | CASE WHEN s = '' THEN a ELSE s + ', ' + a END) AS SOURCE,
       layers                AS LAYERS,
       people                AS PEOPLE,
       round(start, 2)       AS START,
       round(kept, 2)        AS KEPT_BY_PEOPLE,
       CASE WHEN abs(kept - start) < 0.005 THEN 'OK' ELSE 'MISMATCH' END AS CHECK,
       skipped               AS NON_P2P_ROWS_LEFT_OUT,
       round(skipped_amt, 2) AS NON_P2P_AMOUNT
ORDER BY coalesce(toIntegerOrNull(TXN_SL_TAG), 0), TXN_SL_TAG
