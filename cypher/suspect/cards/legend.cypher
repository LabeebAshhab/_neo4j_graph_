// CARD - "What the shapes and colours mean" (report type: Graph)
// The legend nodes built in cypher/suspect/02 section 3.11 - drawn with
// exactly the shapes and colours the main graph uses.
MATCH (l:SLegend)
RETURN l
ORDER BY l.rank
