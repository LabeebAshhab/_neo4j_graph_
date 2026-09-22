// =====================================================================
// KGN4j - step 2 : pull the data out of PostgreSQL into Neo4j
//
// Prerequisites (see README, section "Neo4j setup"):
//   * postgresql-<version>.jar  copied into  <NEO4J_HOME>\plugins
//   * apoc.conf contains         apoc.jdbc.pg.url=...
//   * neo4j.conf contains        dbms.security.procedures.unrestricted=apoc.*
//   * Neo4j restarted afterwards
//
// Smoke test the connection first:
//   CALL apoc.load.jdbc('pg','SELECT count(*) AS n FROM stmt.v_txn_for_graph')
//   YIELD row RETURN row;
// =====================================================================


// ---------------------------------------------------------------------
// 2.0  Clean slate (safe to re-run the whole pipeline)
// ---------------------------------------------------------------------
MATCH (n) DETACH DELETE n;


// ---------------------------------------------------------------------
// 2.1  Accounts + Transactions + directed money-flow relationships
//
//   (from:Account)-[:DEBITED]->(t:Transaction)-[:CREDITED]->(to:Account)
//
// One Transaction node per statement row. The same TXN_ID normally
// appears twice in a statement export (once as D on the sender's
// statement, once as C on the receiver's), so we key on row_key and
// keep both rows - they are two different sources of truth for the
// same movement, and the table card must show both.
// ---------------------------------------------------------------------
CALL apoc.periodic.iterate(
  "CALL apoc.load.jdbc('pg','stmt.v_txn_for_graph') YIELD row RETURN row",
  "
  MERGE (t:Transaction {row_key: row.row_key})
  SET t.unq_id        = row.unq_id,
      t.serial_no     = toInteger(row.serialno),
      t.txn_id        = row.txn_id,
      t.txn_type      = row.txn_type,
      t.account_type  = row.account_type,
      t.channel       = row.channel,
      t.reference     = row.reference,
      t.txn_type_d_c  = row.txn_type_d_c,
      t.status        = row.status,
      t.amount        = toFloat(row.txn_amt),
      t.balance_after = toFloat(row.available_blc_after_txn),
      t.txn_with_info = row.txn_with_info,
      t.stmt_acc      = row.statement_for_acc,
      t.with_acc      = row.txn_with_acc,
      t.txn_date_time = CASE WHEN row.txn_dt_iso    IS NULL THEN NULL ELSE localdatetime(row.txn_dt_iso) END,
      t.from_date     = CASE WHEN row.from_date_iso IS NULL THEN NULL ELSE date(row.from_date_iso)      END,
      t.to_date       = CASE WHEN row.to_date_iso   IS NULL THEN NULL ELSE date(row.to_date_iso)        END,
      t.name          = row.txn_id + ' | ' + row.txn_type + ' | ' + toString(toFloat(row.txn_amt))

  MERGE (src:Account {acc_no: row.from_acc})
    ON CREATE SET src.name = row.from_acc
  MERGE (dst:Account {acc_no: row.to_acc})
    ON CREATE SET dst.name = row.to_acc

  MERGE (src)-[:DEBITED]->(t)
  MERGE (t)-[:CREDITED]->(dst)
  ",
  {batchSize: 5000, parallel: false}
)
YIELD batches, total, errorMessages
RETURN batches, total, errorMessages;


// ---------------------------------------------------------------------
// 2.2  Mark which accounts actually have a statement in the source,
//      and cache their debit / credit totals on the node.
//      `step = 0` makes the Account the root of the click-through chain
//      built in step 3.
// ---------------------------------------------------------------------
MATCH (a:Account)
SET a.step = 0,
    a.is_statement_account = false;

CALL apoc.periodic.iterate(
  "CALL apoc.load.jdbc('pg','stmt.v_account_summary') YIELD row RETURN row",
  "
  MERGE (a:Account {acc_no: row.statement_for_acc})
  SET a.is_statement_account = true,
      a.account_type = row.account_type,
      a.txn_count    = toInteger(row.txn_count),
      a.total_debit  = toFloat(row.total_debit),
      a.total_credit = toFloat(row.total_credit),
      a.step         = 0,
      a.name         = row.statement_for_acc
  ",
  {batchSize: 1000, parallel: false}
)
YIELD batches, total, errorMessages
RETURN batches, total, errorMessages;


// ---------------------------------------------------------------------
// 2.3  What did we get?
// ---------------------------------------------------------------------
MATCH (n) RETURN labels(n) AS label, count(*) AS nodes ORDER BY label;
