// CARD - "1. Pick a customer" (report type: Table)
// Click a CUSTOMER button to set $neodash_trace_acc.
// Same C1..Cn numbering as the Pathao Pay drill-down. CREDITS and
// CREDITED_TK count real statement lines only (:Canon), so the copies
// duplicated in the source are not counted.
MATCH (n:Nav:Customer)
CALL {
  WITH n
  MATCH (t:Canon)
  WHERE t.stmt_acc = n.acc AND t.txn_type_d_c = 'C'
    AND t.txn_date_time IS NOT NULL   // lets the planner use the canon_acc_dc_time index
  RETURN count(t) AS credits, sum(t.amount) AS credited
}
RETURN n.name                                AS CUSTOMER,
       n.acc                                 AS ACCOUNT,
       credits                               AS CREDITS,
       round(credited, 2)                    AS CREDITED_TK,
       CASE WHEN n.acc = $neodash_trace_acc THEN '<< selected' ELSE '' END AS SELECTED
ORDER BY n.cust_no
