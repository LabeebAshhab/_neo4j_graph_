// =====================================================================
// KGN4j - step 5 : prepare the "Money Trail" (credit termination trace)
//
// ADDITIVE ONLY. Nothing built by cypher/02b or cypher/03 is changed or
// deleted: the Pathao Pay drill-down keeps working exactly as before.
// This file only
//   * adds a :Canon label to one representative row of every REAL
//     statement line, plus a `dup_count` property on that row, and
//   * adds one index the trace query needs.
// Re-runnable: it clears its own :Canon labels first.
//
// WHY :Canon EXISTS
// For some statement accounts (C1-C5 in this extract) every real
// statement line is present 414 times, each copy carrying a different
// TXN_ID but the same time, serial, amount, counterparty and balance
// after. Two rows with the same AVAILABLE_BLC_AFTER_TXN at the same
// instant cannot both be real money movements, so they are one line.
// Tracing a credit through the raw rows would "spend" 500 tk on 414
// copies of the first debit. The trace reads only :Canon rows.
//
// The identity of a real line:
//   (stmt_acc, txn_date_time, serial_no, txn_type_d_c, txn_type,
//    amount, balance_after, with_acc)
// The representative is the smallest row_key in the group, so re-runs
// pick the same row.
// =====================================================================


// 5.0  Clear a previous run (labels only - no node is deleted).
MATCH (t:Canon)
CALL { WITH t REMOVE t:Canon REMOVE t.dup_count } IN TRANSACTIONS OF 10000 ROWS;


// 5.1  Mark one row per real statement line, account by account.
MATCH (a:Account {is_statement_account: true})
CALL {
  WITH a
  MATCH (t:Transaction)
  WHERE t.stmt_acc = a.acc_no
  WITH t.txn_date_time AS ts, t.serial_no AS sn, t.txn_type_d_c AS dc,
       t.txn_type AS ty, t.amount AS am, t.balance_after AS bl,
       t.with_acc AS wa, min(t.row_key) AS rk, count(*) AS n
  MATCH (keep:Transaction {row_key: rk})
  SET keep:Canon, keep.dup_count = n
} IN TRANSACTIONS OF 1 ROWS;


// 5.2  Index for the trace: one account's debits (or credits) in time
//      order, read straight off the index so LIMIT stops early.
CREATE INDEX canon_acc_dc_time IF NOT EXISTS
FOR (t:Canon) ON (t.stmt_acc, t.txn_type_d_c, t.txn_date_time);
CREATE INDEX canon_row_key IF NOT EXISTS
FOR (t:Canon) ON (t.row_key);
CALL db.awaitIndexes(600);


// 5.3  Report: raw rows vs real lines per account (duplicated ones first).
MATCH (t:Canon)
WITH t.stmt_acc AS acc, count(*) AS real_lines, sum(t.dup_count) AS raw_rows
RETURN acc, raw_rows, real_lines,
       round(1.0 * raw_rows / real_lines, 1) AS copies_per_line
ORDER BY copies_per_line DESC, raw_rows DESC
LIMIT 20;
