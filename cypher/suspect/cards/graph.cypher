// CARD - "Suspect network" (report type: Graph)
// Draws the base graph (every node without a `parent_key`), plus the
// nodes opened by clicks: a hidden node is drawn when its parent is on
// the clicked node's `chain` (the clicked node and its ancestors).
//   click Others (service fees)  -> the service fee types
//   click More types             -> the smaller transaction types
//   click a type / fee type      -> its suspected wallets
//   click a suspected wallet     -> its TXN_WITH_ACC counterparties
//   click any base node          -> everything closes again
// A stale / unknown focus draws the base graph only.
WITH coalesce($neodash_sus_focus, '') AS fk
OPTIONAL MATCH (f:SNet {key: fk})
WITH coalesce(f.chain, []) AS chain
MATCH (n:SNet)
WHERE n.parent_key IS NULL OR n.parent_key IN chain
WITH collect(n) AS shown
UNWIND shown AS a
MATCH p = (a)-[:SFLOW]->(b)
WHERE b IN shown
RETURN p
