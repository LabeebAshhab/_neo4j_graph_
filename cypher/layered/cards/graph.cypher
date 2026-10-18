// CARD - "Layered money trail" (report type: Graph)
// Opens one level per click.
//   start                 -> every source and the person it paid in layer 1
//   click a person        -> also the people that person paid by P2P
//   click one of those    -> the path stays open, the next level opens
//   click a LAYER header  -> everything closes again
// A node is drawn when it is a source, a layer-1 person, or when its
// parent is on the clicked node's `chain` (the clicked node and the
// people before it). A stale / unknown focus draws the start.
WITH coalesce($neodash_lyr_focus, '') AS fk
OPTIONAL MATCH (f:LNet {key: fk})
WITH coalesce(f.chain, []) AS chain
MATCH (n:LNet)
WHERE n:LHeader OR n.parent_key IS NULL OR n.layer = 1 OR n.parent_key IN chain
WITH collect(n) AS shown
UNWIND shown AS a
OPTIONAL MATCH p = (a)-[:LFLOW]->(b)
WHERE b IN shown
RETURN a, p
