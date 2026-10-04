// =====================================================================
// KGN4j - Suspect Network, step 2 : load the suspected-wallet sheet
//
// SEPARATE PIPELINE. This only creates :SusRow nodes. It never reads or
// touches :Transaction, :Account, :Nav or :Canon, so the Pathao Pay
// drill-down and the Money Trail keep working exactly as before.
//
// Input: <neo4j>\import\suspect_wallet_txn.csv, written by
//   python scripts/export_suspect_csv.py
//
// One :SusRow per sheet row:
//   SUSPECTED_WALLET -> wallet      (one of the 789 suspected customers)
//   TXN_WITH_ACC     -> with_acc    (the wallet it transacted with)
//   TXN_TYPE         -> txn_type    (P2P, CASH OUT, CASH IN, ...)
//   TXN_MODE         -> txn_mode    (CREDIT / DEBIT)
//   TXN_COUNT        -> txn_count
//   TXN_AMOUNT       -> amount
//
// Re-runnable: it deletes its own :SusRow nodes first.
// =====================================================================


// 1.0  Clear a previous load (only :SusRow).
MATCH (r:SusRow)
CALL { WITH r DETACH DELETE r } IN TRANSACTIONS OF 10000 ROWS;


// 1.1  Indexes the graph builder and the table card filter on.
CREATE INDEX susrow_row_no   IF NOT EXISTS FOR (r:SusRow) ON (r.row_no);
CREATE INDEX susrow_wallet   IF NOT EXISTS FOR (r:SusRow) ON (r.wallet);
CREATE INDEX susrow_with_acc IF NOT EXISTS FOR (r:SusRow) ON (r.with_acc);
CREATE INDEX susrow_type     IF NOT EXISTS FOR (r:SusRow) ON (r.txn_type);
CALL db.awaitIndexes(300);


// 1.2  Load. Account numbers stay strings (leading 0).
LOAD CSV WITH HEADERS FROM 'file:///suspect_wallet_txn.csv' AS row
WITH row, linenumber() - 1 AS row_no
WHERE row.SUSPECTED_WALLET IS NOT NULL AND trim(row.SUSPECTED_WALLET) <> ''
CALL {
  WITH row, row_no
  CREATE (r:SusRow {
    row_no:    row_no,
    wallet:    trim(row.SUSPECTED_WALLET),
    with_acc:  trim(coalesce(row.TXN_WITH_ACC, '')),
    txn_type:  trim(coalesce(row.TXN_TYPE, '')),
    txn_mode:  toUpper(trim(coalesce(row.TXN_MODE, ''))),
    txn_count: coalesce(toInteger(row.TXN_COUNT), 0),
    amount:    coalesce(toFloat(row.TXN_AMOUNT), 0.0)
  })
} IN TRANSACTIONS OF 10000 ROWS;


// 1.3  Report - compare with what export_suspect_csv.py printed.
MATCH (r:SusRow)
RETURN count(r)                   AS rows,
       count(DISTINCT r.wallet)   AS suspected_wallets,
       count(DISTINCT r.with_acc) AS txn_with_wallets,
       round(sum(r.amount), 2)    AS total_amount,
       round(sum(r.amount) / 10000000.0, 2) AS total_crore;
