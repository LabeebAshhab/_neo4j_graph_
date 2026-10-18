// =====================================================================
// KGN4j - Layered Trail : remove everything this pipeline created.
// Touches only :LNet, :LLegend and :LyrTxn (and their indexes). The Pathao
// Pay drill-down, the Money Trail and the Suspect Network are not affected.
// =====================================================================
MATCH (n) WHERE n:LNet OR n:LLegend DETACH DELETE n;
MATCH (r:LyrTxn) DETACH DELETE r;
DROP INDEX lnet_key    IF EXISTS;
DROP INDEX lyrtxn_id   IF EXISTS;
DROP INDEX lyrtxn_from IF EXISTS;
DROP INDEX lyrtxn_with IF EXISTS;
