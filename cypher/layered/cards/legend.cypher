// CARD - "What the shapes and colours mean" (report type: Graph)
// The legend nodes built in cypher/layered/01_build_layered_graph.cypher section 2.9 - drawn with
// exactly the shapes and colours the main graph uses.
MATCH (l:LLegend)
RETURN l
ORDER BY l.rank
