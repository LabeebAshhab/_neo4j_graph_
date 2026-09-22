// =====================================================================
// KGN4j - step 3 : build the click-through chain that NeoDash expands
//
// The chain is a straight line of nodes, each carrying a `step` number:
//
//   (:Account  step=0)                the statement account you clicked
//        |:FLOW
//   (:DebitTotal step=1)              "DEBIT 45000" - total debited
//        |:FLOW
//   (:CreditLeg step=2  seq=1)        first credit out of that debit
//        |:FLOW
//   (:CreditLeg step=3  seq=2)        next one, cumulative total grows
//        |:FLOW
//   (:CreditLeg step=N  is_last=true) cumulative == debited -> chain ends
//
// NeoDash only ever renders nodes with  step <= (clicked step) + 1,
// which is what produces the one-node-at-a-time expansion. Because the
// chain is precomputed here, the dashboard query stays trivial and fast.
//
// Re-runnable: it drops and rebuilds the whole chain.
// =====================================================================


// ---------------------------------------------------------------------
// 3.0  Drop any previous chain
// ---------------------------------------------------------------------
MATCH (n) WHERE n:DebitTotal OR n:CreditLeg DETACH DELETE n;
MATCH ()-[r:FLOW]->() DELETE r;

// Every chain node carries a `focus` key of the form  <root>#<step>.
// The dashboard sets one parameter from it on click, and because the
// key contains the root account, a stale click on a previous account is
// ignored automatically - switching accounts in the table collapses the
// graph back to a single node with no extra reset step.
MATCH (a:Account)
SET a.step = 0,
    a.focus = a.acc_no + '#0';


// ---------------------------------------------------------------------
// 3.1  DebitTotal node - one per statement account that debited money
// ---------------------------------------------------------------------
MATCH (a:Account {is_statement_account: true})
CALL {
  WITH a
  // only the account's OWN statement rows marked 'D'.
  // The counterparty's mirror row (same TXN_ID, marked 'C') is a
  // separate Transaction node and must not be counted twice here.
  MATCH (a)-[:DEBITED]->(t:Transaction)-[:CREDITED]->(b:Account)
  WHERE t.txn_type_d_c = 'D' AND t.stmt_acc = a.acc_no
  WITH t, b ORDER BY t.txn_date_time ASC, t.serial_no ASC
  RETURN collect({txn: t, other: b}) AS legs, sum(t.amount) AS total_debit
}
WITH a, legs, total_debit
WHERE total_debit > 0
MERGE (d:DebitTotal {acc_no: a.acc_no})
SET d.step        = 1,
    d.root        = a.acc_no,
    d.total_debit = total_debit,
    d.leg_count   = size(legs),
    d.focus       = a.acc_no + '#1',
    d.name        = 'DEBIT ' + toString(total_debit),
    d.title       = 'Total debited from ' + a.acc_no
MERGE (a)-[:FLOW]->(d);


// ---------------------------------------------------------------------
// 3.2  CreditLeg nodes - the individual outgoing transactions, in time
//      order, each holding the running total. Generation stops at the
//      first leg where the running total has matched the debited amount.
// ---------------------------------------------------------------------
MATCH (a:Account {is_statement_account: true})-[:FLOW]->(d:DebitTotal)
CALL {
  WITH a
  MATCH (a)-[:DEBITED]->(t:Transaction)-[:CREDITED]->(b:Account)
  WHERE t.txn_type_d_c = 'D' AND t.stmt_acc = a.acc_no
  WITH t, b ORDER BY t.txn_date_time ASC, t.serial_no ASC
  RETURN collect({txn: t, other: b}) AS legs
}
WITH a, d, legs, d.total_debit AS total_debit
UNWIND range(0, size(legs) - 1) AS i
WITH a, d, legs, total_debit, i,
     reduce(s = 0.0, j IN range(0, i)     | s + legs[j].txn.amount) AS cum,
     reduce(s = 0.0, j IN range(0, i - 1) | s + legs[j].txn.amount) AS prev_cum
// stop condition: once the previous leg already matched the debited
// amount there is nothing left to trace, so no further legs are created.
WHERE i = 0 OR prev_cum < total_debit - 0.005
WITH a, d, total_debit, i, cum, legs[i] AS leg
MERGE (c:CreditLeg {leg_key: a.acc_no + '#' + toString(i + 1)})
SET c.root        = a.acc_no,
    c.seq         = i + 1,
    c.step        = i + 2,
    c.focus       = a.acc_no + '#' + toString(i + 2),
    c.txn_id      = leg.txn.txn_id,
    c.txn_type    = leg.txn.txn_type,
    c.channel     = leg.txn.channel,
    c.status      = leg.txn.status,
    c.txn_date_time = leg.txn.txn_date_time,
    c.amount      = leg.txn.amount,
    c.cumulative  = cum,
    c.remaining   = total_debit - cum,
    c.total_debit = total_debit,
    c.to_account  = leg.other.acc_no,
    c.info        = leg.txn.txn_with_info,
    c.is_last     = (cum >= total_debit - 0.005),
    c.name        = 'CREDIT ' + toString(leg.txn.amount) + ' -> ' + leg.other.acc_no,
    c.title       = leg.txn.txn_id + '  (' + toString(cum) + ' of ' + toString(total_debit) + ')'
WITH c, leg.other AS other_acc, leg.txn AS txn_node
MERGE (c)-[:TO_ACCOUNT]->(other_acc)
MERGE (c)-[:OF_TXN]->(txn_node);


// ---------------------------------------------------------------------
// 3.3  Wire the chain together:  DebitTotal -> leg1 -> leg2 -> ...
// ---------------------------------------------------------------------
MATCH (d:DebitTotal)
MATCH (c:CreditLeg {seq: 1})
WHERE c.root = d.acc_no
MERGE (d)-[:FLOW]->(c);

MATCH (c1:CreditLeg)
MATCH (c2:CreditLeg {root: c1.root})
WHERE c2.seq = c1.seq + 1
MERGE (c1)-[:FLOW]->(c2);


// ---------------------------------------------------------------------
// 3.4  Verify - every chain must end with cumulative == total_debit
// ---------------------------------------------------------------------
MATCH (a:Account)-[:FLOW]->(d:DebitTotal)
OPTIONAL MATCH (d)-[:FLOW*]->(last:CreditLeg {is_last: true})
RETURN a.acc_no          AS account,
       d.total_debit     AS debited,
       d.leg_count       AS legs_available,
       last.seq          AS legs_needed,
       last.cumulative   AS credited_sum,
       CASE WHEN last IS NULL THEN 'NO CHAIN'
            WHEN abs(last.cumulative - d.total_debit) < 0.005 THEN 'BALANCED'
            ELSE 'MISMATCH' END AS chain_status
ORDER BY account;
