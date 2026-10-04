// =====================================================================
// KGN4j - Suspect Network : remove everything this pipeline created.
// Touches only :SNet, :SLegend and :SusRow (and their indexes). The Pathao Pay
// drill-down and the Money Trail are not affected.
// =====================================================================
MATCH (n) WHERE n:SNet OR n:SLegend DETACH DELETE n;
MATCH (r:SusRow)
CALL { WITH r DETACH DELETE r } IN TRANSACTIONS OF 10000 ROWS;
DROP INDEX susrow_row_no   IF EXISTS;
DROP INDEX susrow_wallet   IF EXISTS;
DROP INDEX susrow_with_acc IF EXISTS;
DROP INDEX susrow_type     IF EXISTS;
