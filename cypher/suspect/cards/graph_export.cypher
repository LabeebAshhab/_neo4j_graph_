// CARD - "Graph data (export)" (report type: Table, CSV download on)
// One row per relationship currently drawn in the graph - the same
// reveal rule as cards/graph.cypher - so the export always matches the
// picture. FROM / TO give what is written inside and beside each node.
WITH coalesce($neodash_sus_focus, '') AS fk
OPTIONAL MATCH (f:SNet {key: fk})
WITH coalesce(f.chain, []) AS chain
MATCH (n:SNet)
WHERE n.parent_key IS NULL OR n.parent_key IN chain
WITH collect(n) AS shown
UNWIND shown AS a
MATCH (a)-[r:SFLOW]->(b)
WHERE b IN shown
RETURN a.role                          AS FROM_NODE,
       a.name                          AS FROM_INSIDE,
       coalesce(a.outer, '')           AS FROM_OUTSIDE,
       coalesce(r.amount_text, r.name, '') AS RELATION,
       r.amount                        AS AMOUNT_TK,
       b.role                          AS TO_NODE,
       b.name                          AS TO_INSIDE,
       coalesce(b.outer, '')           AS TO_OUTSIDE
ORDER BY a.pin_y, a.pin_x, b.pin_y
