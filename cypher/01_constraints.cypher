// =====================================================================
// KGN4j - step 1 : constraints and indexes
// Run in Neo4j Browser (http://localhost:7474) against database `neo4j`.
// Run the whole file at once; each statement ends with a semicolon.
// =====================================================================

CREATE CONSTRAINT account_acc_no IF NOT EXISTS
FOR (a:Account) REQUIRE a.acc_no IS UNIQUE;

CREATE CONSTRAINT txn_row_key IF NOT EXISTS
FOR (t:Transaction) REQUIRE t.row_key IS UNIQUE;

// every node of the Pathao Pay drill-down tree
CREATE CONSTRAINT nav_key IF NOT EXISTS
FOR (n:Nav) REQUIRE n.key IS UNIQUE;

CREATE INDEX txn_dc IF NOT EXISTS
FOR (t:Transaction) ON (t.txn_type_d_c);

CREATE INDEX txn_id_idx IF NOT EXISTS
FOR (t:Transaction) ON (t.txn_id);

// the drill-down reveal rule filters on these two
CREATE INDEX nav_parent IF NOT EXISTS
FOR (n:Nav) ON (n.parent_key);

CREATE INDEX nav_path IF NOT EXISTS
FOR (n:Nav) ON (n.path);

// cypher/03 groups transactions by these
CREATE INDEX txn_stmt_acc IF NOT EXISTS
FOR (t:Transaction) ON (t.stmt_acc);

CREATE INDEX txn_type_idx IF NOT EXISTS
FOR (t:Transaction) ON (t.txn_type);

// Composite indexes. At ~134k rows per account, cypher/03 runs roughly
// 500 per-account/per-type aggregations; without these each one degrades
// into a scan of that account's whole history and the build takes tens of
// minutes instead of a couple.
CREATE INDEX txn_acc_dc IF NOT EXISTS
FOR (t:Transaction) ON (t.stmt_acc, t.txn_type_d_c);

CREATE INDEX txn_acc_dc_type IF NOT EXISTS
FOR (t:Transaction) ON (t.stmt_acc, t.txn_type_d_c, t.txn_type);

SHOW CONSTRAINTS;
