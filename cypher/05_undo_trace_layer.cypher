// =====================================================================
// KGN4j - undo step 5 : remove everything cypher/05_build_trace_layer
// added. The Pathao Pay drill-down never used any of it, so the database
// is back exactly as cypher/02b + cypher/03 left it.
// =====================================================================
MATCH (t:Canon)
CALL { WITH t REMOVE t:Canon REMOVE t.dup_count } IN TRANSACTIONS OF 10000 ROWS;

DROP INDEX canon_acc_dc_time IF EXISTS;
DROP INDEX canon_row_key IF EXISTS;
