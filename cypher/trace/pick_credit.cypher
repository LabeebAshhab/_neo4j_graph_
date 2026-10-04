// CARD - "2. Pick a credit to trace" (report type: Table)
// Every credit into the selected customer's account, oldest first.
// Click TRACE to set $neodash_trace_credit (from the hidden __key column).
// Use the column filter / sort in the table header to find a particular
// date or amount.
MATCH (c:Canon)
WHERE c.stmt_acc = $neodash_trace_acc
  AND c.txn_type_d_c = 'C'
  AND c.txn_date_time IS NOT NULL   // lets the planner use the canon_acc_dc_time index
RETURN 'TRACE'            AS TRACE,
       c.txn_date_time    AS TXN_DATE_TIME,
       c.txn_type         AS TXN_TYPE,
       c.amount           AS TXN_AMT,
       c.with_acc         AS FROM_ACC,
       c.balance_after    AS AVAILABLE_BLC_AFTER_TXN,
       CASE WHEN c.row_key = $neodash_trace_credit THEN '<< tracing' ELSE '' END AS SELECTED,
       c.row_key          AS __key
ORDER BY TXN_DATE_TIME, c.serial_no
LIMIT 5000
