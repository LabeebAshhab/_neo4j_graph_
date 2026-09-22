// =====================================================================
// KGN4j - step 2 (ALTERNATIVE) : load via CSV export instead of JDBC
//
// Use this file INSTEAD OF cypher/02_load_from_postgres.cypher when your
// Neo4j has no `apoc.load.jdbc` - which is the case on 2025.x / 2026.x,
// where load.jdbc sits in APOC Extended and no matching Extended build
// exists. Nothing else in the project changes: this produces exactly the
// same graph, so cypher/03 and the dashboard work unmodified.
//
// ---------------------------------------------------------------------
// FIRST, in pgAdmin (once per data refresh):
//
//   1. Run sql/01_view.sql so public.v_txn_for_graph and
//      public.v_account_summary exist.
//   2. Export both into Neo4j's import folder. On a large table use
//      server-side COPY, not the results-grid download:
//
//        COPY (SELECT * FROM public.v_txn_for_graph)
//        TO 'C:\neo4j\neo4j-community-2026.08.1\import\txn_for_graph.csv'
//        WITH (FORMAT csv, HEADER true);
//
//        COPY (SELECT * FROM public.v_account_summary)
//        TO 'C:\neo4j\neo4j-community-2026.08.1\import\account_summary.csv'
//        WITH (FORMAT csv, HEADER true);
//
//      Neo4j only reads CSVs from its own import folder.
//
// Sanity check the file is visible to Neo4j before loading:
//   LOAD CSV WITH HEADERS FROM 'file:///txn_for_graph.csv' AS row
//   RETURN row LIMIT 3;
//
// SCALE: this loads in batched transactions and is safe on millions of
// rows, but it is not instant - expect roughly 10-20 minutes per few
// million rows, and make sure the constraints in cypher/01 exist FIRST
// or every MERGE degrades to a full scan.
// =====================================================================


// ---------------------------------------------------------------------
// 2b.0  Clean slate.
//
// ON A LARGE TABLE do NOT use `MATCH (n) DETACH DELETE n` - it builds one
// enormous transaction and will run the heap out. Delete in batches, or
// (much faster on millions of rows) stop Neo4j, delete the database
// directory and let it recreate empty.
// ---------------------------------------------------------------------
MATCH (n)
CALL { WITH n DETACH DELETE n } IN TRANSACTIONS OF 10000 ROWS;


// ---------------------------------------------------------------------
// 2b.1  Accounts + Transactions + directed money-flow relationships
//
//   (from:Account)-[:DEBITED]->(t:Transaction)-[:CREDITED]->(to:Account)
//
// Identical model to cypher/02. Note every value arrives as a string
// from CSV, so each one is cast explicitly - that is the only real
// difference from the JDBC path.
// ---------------------------------------------------------------------
// LOAD CSV stays OUTSIDE the CALL subquery. `IN TRANSACTIONS` batches the
// rows flowing INTO the subquery, so if LOAD CSV were inside it there would
// be nothing to batch and all 6.7M rows would run as one transaction -
// which is exactly how this failed the first time.
LOAD CSV WITH HEADERS FROM 'file:///txn_for_graph.csv' AS row
WITH row
WHERE row.statement_for_acc IS NOT NULL AND trim(row.statement_for_acc) <> ''
  AND row.txn_id IS NOT NULL AND trim(row.txn_id) <> ''
CALL {
  WITH row

  // row_key is built HERE, not taken from the CSV.
  // The source UNQ_ID column is a constant tag ('NGD_PATHAO_PAY_V4') on
  // every row, so it identifies the export, not the transaction. Using it
  // would MERGE all 6.7M rows onto a single node.
  // (statement_for_acc, txn_id, serialno, D/C) is unique - verified over
  // a 1.5M row sample with zero collisions.
  WITH row,
       row.statement_for_acc + '|' + row.txn_id + '|' +
       coalesce(row.serialno, '') + '|' + row.txn_type_d_c AS rk
  MERGE (t:Transaction {row_key: rk})
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
      // dates are stored as text exactly as the source has them.
      // Nothing in the graph build sorts or filters by date, and parsing
      // 6.7M values buys nothing but a slower load.
      t.txn_date_time = row.txn_date_time,
      t.from_date     = row.from_date,
      t.to_date       = row.to_date

  MERGE (src:Account {acc_no: row.from_acc})
    ON CREATE SET src.name = row.from_acc
  MERGE (dst:Account {acc_no: row.to_acc})
    ON CREATE SET dst.name = row.to_acc

  MERGE (src)-[:DEBITED]->(t)
  MERGE (t)-[:CREDITED]->(dst)
} IN TRANSACTIONS OF 10000 ROWS;


// ---------------------------------------------------------------------
// 2b.2  Mark the statement accounts and cache their totals
// ---------------------------------------------------------------------
MATCH (a:Account)
SET a.step = 0,
    a.is_statement_account = false;

LOAD CSV WITH HEADERS FROM 'file:///account_summary.csv' AS row
WITH row
WHERE row.statement_for_acc IS NOT NULL AND trim(row.statement_for_acc) <> ''
MERGE (a:Account {acc_no: row.statement_for_acc})
SET a.is_statement_account = true,
    a.account_type = row.account_type,
    a.txn_count    = toInteger(row.txn_count),
    a.total_debit  = toFloat(row.total_debit),
    a.total_credit = toFloat(row.total_credit),
    a.step         = 0,
    a.name         = row.statement_for_acc;


// ---------------------------------------------------------------------
// 2b.3  What did we get?  Compare these counts against the row counts
//       pgAdmin reported for the two views.
// ---------------------------------------------------------------------
MATCH (n) RETURN labels(n) AS label, count(*) AS nodes ORDER BY label;
MATCH ()-[r]->() RETURN type(r) AS rel_type, count(*) AS count ORDER BY rel_type;


// ---------------------------------------------------------------------
// NEXT: run cypher/03_build_nav_graph.cypher, then cypher/04_verify.cypher.
//       Neither knows or cares how the rows arrived.
// ---------------------------------------------------------------------
