// =====================================================================
// KGN4j - step 3 : build the Pathao Pay drill-down graph
//
// The navigation tree NeoDash expands one level per click:
//
//   (1) Pathao Pay
//        | rel = total credited, e.g. "138.29 Crore tk"
//   (2) Customers 1-10 of 380     <- click again for 11-20, 21-30, ...
//        | rel = that customer's credited amount
//   (3) C1 / C2 / C3 ... Cn                 <- ten per page
//        | rel = that customer's total activity (debit + credit)
//   (4) Customer-<STATEMENT_FOR_ACC>
//        | rel = total activity (debit + credit)
//   (5) TXN_TYPE_D_C
//        |                          \
//        | rel = credited            | rel = debited
//   (6) Credit                   (7) Debit
//        |                            | rel = debited
//        |                        (8) TXN_TYPE
//        |                            |
//        +--------------+-------------+
//                       | rel = amount per type
//   (9) P2P / TOP UP / CASH OUT / PAYMENT ...
//                       | rel = amount with that counterparty
//  (10) Customer-<TXN_WITH_ACC> ... plus an END node
//
// Credit expands STRAIGHT into its transaction-type nodes; Debit goes
// through the extra "TXN_TYPE" hub node first. That asymmetry is what
// the node list asks for - say the word and the credit branch gets its
// own hub too.
//
// LEVEL 9 -> 10 EXPANSION
// Counterparties are emitted highest-amount-first and the running total
// is accumulated until it covers that transaction type's amount - i.e.
// until the side being drilled into balances - and then an END node
// closes the branch. Where that balance point sits past
// `max_counterparties` the tail is rolled into a single "Others (n
// customers)" node holding exactly the remainder, so the branch still
// balances without a fan-out nobody can read.
//
// AMOUNTS
// Every relationship caption is short-form Bangladeshi notation:
//   1382920243.4999224  ->  "138.29 Crore tk"
// The exact value stays on the relationship as `amount`, so hover and
// the table still show the real number.
//
// SOURCE COLUMNS USED
//   STATEMENT_FOR_ACC  -> the customer whose statement a row belongs to
//   TXN_WITH_ACC       -> the counterparty
//   TXN_TYPE           -> P2P / TOP UP / CASH OUT / PAYMENT / ...
//   TXN_TYPE_D_C       -> 'D' or 'C'
//   TXN_AMT            -> the amount, summed into relationship captions
//
// PREREQUISITE: the :Transaction / :Account graph from
//   cypher/02b_load_from_csv.cypher
//
// CONFIGURE FIRST -----------------------------------------------------
// `pathao_acc` selects which credits count as "credited from Pathao Pay".
//   * leave it NULL to treat every credit on a customer statement as
//     coming from the platform
//   * set it to the Pathao Pay settlement account number to count only
//     credits whose TXN_WITH_ACC is that account
// ---------------------------------------------------------------------
:param pathao_name => 'Pathao Pay';
:param pathao_acc  => null;

// SCALE CAPS.
//   top_customers       - how many customers to build, highest credited
//                         first. A guard; set well above your real count.
//   max_counterparties  - how many level-10 nodes to draw per transaction
//                         type before rolling the rest into one "Others"
//                         node. The expansion usually stops earlier, on
//                         its own, once the amounts balance. Raising this
//                         shows a longer tail; it does not change any
//                         total, because Others absorbs whatever is left.
//   page_size           - customers shown per click at level 2. 380 nodes
//                         at once is unreadable; ten is a screenful.
//                         Clicking the Customers node again brings the
//                         next `page_size`, wrapping at the end.
:param top_customers      => 500;
:param max_counterparties => 100;
:param page_size          => 10;


// ---------------------------------------------------------------------
// 3.0  Drop any previous navigation graph. :Transaction and :Account
//      are untouched - this only rebuilds the drill-down layer.
// ---------------------------------------------------------------------
MATCH (n:Nav) DETACH DELETE n;


// ---------------------------------------------------------------------
// 3.1  Level 1 - the Pathao Pay node.
//      `path` is a materialized path with a trailing slash. The reveal
//      rule in the dashboard is a STARTS WITH test against it, and the
//      trailing slash is what stops 'cust:1' matching 'cust:10'.
//
//      The f_* properties are the TABLE FILTER for this node: the
//      transactions card reads them off whichever node is in focus, so
//      selecting a node narrows the dataframe to exactly that node's
//      rows. All null here = the whole table.
// ---------------------------------------------------------------------
MERGE (r:Nav:Provider {key: 'root'})
SET r.name       = $pathao_name,
    r.level      = 1,
    r.path       = '/root/',
    r.parent_key = null,
    r.click      = 'root',
    r.f_acc      = null,
    r.f_dc       = null,
    r.f_type     = null,
    r.f_cp       = null;


// ---------------------------------------------------------------------
// 3.2  Level 2 - the "Customers" node, PAGED.
//
//      380 customers drawn at once is unreadable, so the level is cut
//      into pages of `page_size`. Each page is its own node captioned
//      "Customers 1-10 of 380", and its `click` points at the NEXT page,
//      so clicking the Customers node again swaps in the next ten. The
//      last page wraps back to the first.
//
//      Every page hangs off the root with `parent_key = 'root'`, but
//      only page 1 is revealed automatically - the graph card's reveal
//      rule filters the others out with `n.page = 1`. The only way to
//      reach page 2 is to click page 1, which is what makes the paging
//      feel like one node cycling rather than 38 nodes fanning out.
//
//      Relationship caption = total credited from Pathao Pay. It is the
//      same figure on every page: the edge describes the whole customer
//      base, not the ten currently on screen. Each page carries its own
//      ten-customer subtotal as `page_credit` for hover.
// ---------------------------------------------------------------------
MATCH (r:Nav {key: 'root'})
CALL {
  MATCH (t:Transaction)
  WHERE t.txn_type_d_c = 'C'
    AND ($pathao_acc IS NULL OR t.with_acc = $pathao_acc)
  RETURN sum(t.amount)              AS total_credit,
         count(DISTINCT t.stmt_acc) AS customer_count
}
CALL {
  MATCH (t:Transaction)
  WHERE t.txn_type_d_c = 'C'
    AND ($pathao_acc IS NULL OR t.with_acc = $pathao_acc)
  WITH t.stmt_acc AS acc, sum(t.amount) AS credited
  ORDER BY credited DESC, acc ASC
  LIMIT $top_customers
  RETURN collect({acc: acc, credited: credited}) AS top
}
WITH r, total_credit, customer_count, top,
     toInteger(ceil(1.0 * size(top) / $page_size)) AS page_count
UNWIND range(1, page_count) AS pg
WITH r, total_credit, customer_count, top, page_count, pg,
     $page_size * (pg - 1) AS start
WITH r, total_credit, customer_count, top, page_count, pg, start,
     top[start .. start + $page_size] AS slice
MERGE (p:Nav:CustomerPage {key: 'cpage:' + toString(pg)})
SET p.name           = 'Customers ' + toString(start + 1) + '-' +
                       toString(start + size(slice)) + ' of ' + toString(size(top)),
    p.level          = 2,
    p.path           = '/root/cpage:' + toString(pg) + '/',
    p.parent_key     = 'root',
    p.page           = pg,
    p.page_count     = page_count,
    // click the page node and the NEXT ten arrive; the last wraps to 1
    p.click          = 'cpage:' + toString(CASE WHEN pg = page_count THEN 1 ELSE pg + 1 END),
    p.total_credit   = total_credit,
    p.page_credit    = reduce(s = 0.0, x IN slice | s + x.credited),
    p.customer_count = customer_count,
    p.f_acc          = null,
    p.f_dc           = null,
    p.f_type         = null,
    p.f_cp           = null
MERGE (r)-[e:EXPANDS]->(p)
SET e.amount = total_credit,
    e.name   = CASE
                 WHEN abs(coalesce(total_credit,0.0)) >= 10000000 THEN toString(round(total_credit/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(total_credit,0.0)) >= 100000   THEN toString(round(total_credit/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(total_credit,0.0)) >= 1000     THEN toString(round(total_credit/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(total_credit,0.0), 2)) + ' tk'
               END

// ---------------------------------------------------------------------
// 3.3  Level 3 - one node per customer, named C1 .. Cn, ten per page.
//      Numbering is GLOBAL and follows credited amount, highest first:
//      page 1 holds C1-C10, page 2 holds C11-C20, and so on, so a
//      customer's number never changes with the page size.
//      Relationship caption = that customer's credited amount.
// ---------------------------------------------------------------------
WITH p, start, slice
UNWIND range(0, size(slice) - 1) AS j
WITH p, start + j + 1 AS cust_no, slice[j].acc AS acc, slice[j].credited AS credited
MERGE (c:Nav:Customer {key: 'cust:' + acc})
SET c.name       = 'C' + toString(cust_no),
    c.acc        = acc,
    c.cust_no    = cust_no,
    c.level      = 3,
    c.path       = p.path + 'cust:' + acc + '/',
    c.parent_key = p.key,
    c.click      = 'cust:' + acc,
    c.credited   = credited,
    c.f_acc      = acc,
    c.f_dc       = null,
    c.f_type     = null,
    c.f_cp       = null
MERGE (p)-[e:EXPANDS]->(c)
SET e.amount = credited,
    e.name   = CASE
                 WHEN abs(coalesce(credited,0.0)) >= 10000000 THEN toString(round(credited/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(credited,0.0)) >= 100000   THEN toString(round(credited/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(credited,0.0)) >= 1000     THEN toString(round(credited/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(credited,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.4  Level 4 - "Customer-<STATEMENT_FOR_ACC>".
//      This is where the actual account number shows up: click C2 and
//      you get "Customer-3827837287" beside it.
//      Relationship caption = that customer's TOTAL activity, debit and
//      credit together.
// ---------------------------------------------------------------------
MATCH (c:Nav:Customer)
CALL {
  WITH c
  MATCH (t:Transaction)
  WHERE t.stmt_acc = c.acc
  RETURN sum(t.amount) AS total_all, count(t) AS cnt_all
}
MERGE (d:Nav:CustomerAcc {key: 'acc:' + c.acc})
SET d.name       = 'Customer-' + c.acc,
    d.acc        = c.acc,
    d.level      = 4,
    d.path       = c.path + 'acc/',
    d.parent_key = c.key,
    d.click      = 'acc:' + c.acc,
    d.total_all  = total_all,
    d.txn_count  = cnt_all,
    d.f_acc      = c.acc,
    d.f_dc       = null,
    d.f_type     = null,
    d.f_cp       = null
MERGE (c)-[e:EXPANDS]->(d)
SET e.amount = total_all,
    e.name   = CASE
                 WHEN abs(coalesce(total_all,0.0)) >= 10000000 THEN toString(round(total_all/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(total_all,0.0)) >= 100000   THEN toString(round(total_all/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(total_all,0.0)) >= 1000     THEN toString(round(total_all/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(total_all,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.5  Level 5 - "TXN_TYPE_D_C", the split point.
//      Relationship caption = total activity (debit + credit).
// ---------------------------------------------------------------------
MATCH (d:Nav:CustomerAcc)
MERGE (x:Nav:TxnTypeDC {key: 'dc:' + d.acc})
SET x.name       = 'TXN_TYPE_D_C',
    x.acc        = d.acc,
    x.level      = 5,
    x.path       = d.path + 'dc/',
    x.parent_key = d.key,
    x.click      = 'dc:' + d.acc,
    x.total_all  = d.total_all,
    x.f_acc      = d.acc,
    x.f_dc       = null,
    x.f_type     = null,
    x.f_cp       = null
MERGE (d)-[e:EXPANDS]->(x)
SET e.amount = d.total_all,
    e.name   = CASE
                 WHEN abs(coalesce(d.total_all,0.0)) >= 10000000 THEN toString(round(d.total_all/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(d.total_all,0.0)) >= 100000   THEN toString(round(d.total_all/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(d.total_all,0.0)) >= 1000     THEN toString(round(d.total_all/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(d.total_all,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.6  Level 6 - the "Credit" branch. Relationship caption = credited.
//      Clicking it expands straight into that customer's CREDITED
//      transaction types (section 3.9a).
// ---------------------------------------------------------------------
MATCH (x:Nav:TxnTypeDC)
CALL {
  WITH x
  MATCH (t:Transaction)
  WHERE t.stmt_acc = x.acc AND t.txn_type_d_c = 'C'
  RETURN sum(t.amount) AS total, count(t) AS cnt
}
MERGE (c:Nav:CreditNode {key: 'credit:' + x.acc})
SET c.name       = 'Credit',
    c.acc        = x.acc,
    c.level      = 6,
    c.path       = x.path + 'credit/',
    c.parent_key = x.key,
    c.click      = 'credit:' + x.acc,
    c.total      = total,
    c.txn_count  = cnt,
    c.f_acc      = x.acc,
    c.f_dc       = 'C',
    c.f_type     = null,
    c.f_cp       = null
MERGE (x)-[e:EXPANDS]->(c)
SET e.amount = total,
    e.name   = CASE
                 WHEN abs(coalesce(total,0.0)) >= 10000000 THEN toString(round(total/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(total,0.0)) >= 100000   THEN toString(round(total/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(total,0.0)) >= 1000     THEN toString(round(total/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(total,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.7  Level 7 - the "Debit" branch. Relationship caption = debited.
// ---------------------------------------------------------------------
MATCH (x:Nav:TxnTypeDC)
CALL {
  WITH x
  MATCH (t:Transaction)
  WHERE t.stmt_acc = x.acc AND t.txn_type_d_c = 'D'
  RETURN sum(t.amount) AS total, count(t) AS cnt
}
MERGE (dn:Nav:DebitNode {key: 'debit:' + x.acc})
SET dn.name       = 'Debit',
    dn.acc        = x.acc,
    dn.level      = 7,
    dn.path       = x.path + 'debit/',
    dn.parent_key = x.key,
    dn.click      = 'debit:' + x.acc,
    dn.total      = total,
    dn.txn_count  = cnt,
    dn.f_acc      = x.acc,
    dn.f_dc       = 'D',
    dn.f_type     = null,
    dn.f_cp       = null
MERGE (x)-[e:EXPANDS]->(dn)
SET e.amount = total,
    e.name   = CASE
                 WHEN abs(coalesce(total,0.0)) >= 10000000 THEN toString(round(total/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(total,0.0)) >= 100000   THEN toString(round(total/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(total,0.0)) >= 1000     THEN toString(round(total/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(total,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.8  Level 8 - "TXN_TYPE", the hub under Debit.
//      Relationship caption = the debited total, again.
// ---------------------------------------------------------------------
MATCH (dn:Nav:DebitNode)
MERGE (h:Nav:TxnTypeHub {key: 'dtype:' + dn.acc})
SET h.name       = 'TXN_TYPE',
    h.acc        = dn.acc,
    h.level      = 8,
    h.path       = dn.path + 'types/',
    h.parent_key = dn.key,
    h.click      = 'dtype:' + dn.acc,
    h.total      = dn.total,
    h.f_acc      = dn.acc,
    h.f_dc       = 'D',
    h.f_type     = null,
    h.f_cp       = null
MERGE (dn)-[e:EXPANDS]->(h)
SET e.amount = dn.total,
    e.name   = CASE
                 WHEN abs(coalesce(dn.total,0.0)) >= 10000000 THEN toString(round(dn.total/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(dn.total,0.0)) >= 100000   THEN toString(round(dn.total/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(dn.total,0.0)) >= 1000     THEN toString(round(dn.total/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(dn.total,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.9  Level 9 - the transaction types: P2P, TOP UP, CASH OUT,
//      PAYMENT and the rest.
//
//      Built TWICE from the same shape of query:
//        * under "Credit"   (parent = credit:<acc>)  for TXN_TYPE_D_C='C'
//        * under "TXN_TYPE" (parent = dtype:<acc>)   for TXN_TYPE_D_C='D'
//      `dc` on the node keeps the two sides apart and drives both the
//      counterparty expansion below and the table filter.
//      Relationship caption = amount moved through that type.
// ---------------------------------------------------------------------
// 3.9a  credited types, hanging off the Credit node
MATCH (p:Nav:CreditNode)
MATCH (t:Transaction)
WHERE t.stmt_acc = p.acc
  AND t.txn_type_d_c = 'C'
  AND t.txn_type IS NOT NULL
WITH p, t.txn_type AS ty, sum(t.amount) AS amt, count(t) AS cnt
MERGE (n:Nav:TxnTypeNode {key: 'type:' + p.acc + ':C:' + ty})
SET n.name       = ty,
    n.acc        = p.acc,
    n.txn_type   = ty,
    n.dc         = 'C',
    n.level      = 9,
    n.path       = p.path + 'type:' + ty + '/',
    n.parent_key = p.key,
    n.click      = 'type:' + p.acc + ':C:' + ty,
    n.amount     = amt,
    n.txn_count  = cnt,
    n.f_acc      = p.acc,
    n.f_dc       = 'C',
    n.f_type     = ty,
    n.f_cp       = null
MERGE (p)-[e:EXPANDS]->(n)
SET e.amount = amt,
    e.name   = CASE
                 WHEN abs(coalesce(amt,0.0)) >= 10000000 THEN toString(round(amt/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(amt,0.0)) >= 100000   THEN toString(round(amt/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(amt,0.0)) >= 1000     THEN toString(round(amt/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(amt,0.0), 2)) + ' tk'
               END;

// 3.9b  debited types, hanging off the TXN_TYPE hub
MATCH (p:Nav:TxnTypeHub)
MATCH (t:Transaction)
WHERE t.stmt_acc = p.acc
  AND t.txn_type_d_c = 'D'
  AND t.txn_type IS NOT NULL
WITH p, t.txn_type AS ty, sum(t.amount) AS amt, count(t) AS cnt
MERGE (n:Nav:TxnTypeNode {key: 'type:' + p.acc + ':D:' + ty})
SET n.name       = ty,
    n.acc        = p.acc,
    n.txn_type   = ty,
    n.dc         = 'D',
    n.level      = 9,
    n.path       = p.path + 'type:' + ty + '/',
    n.parent_key = p.key,
    n.click      = 'type:' + p.acc + ':D:' + ty,
    n.amount     = amt,
    n.txn_count  = cnt,
    n.f_acc      = p.acc,
    n.f_dc       = 'D',
    n.f_type     = ty,
    n.f_cp       = null
MERGE (p)-[e:EXPANDS]->(n)
SET e.amount = amt,
    e.name   = CASE
                 WHEN abs(coalesce(amt,0.0)) >= 10000000 THEN toString(round(amt/10000000.0, 2)) + ' Crore tk'
                 WHEN abs(coalesce(amt,0.0)) >= 100000   THEN toString(round(amt/100000.0, 2))   + ' Lakh tk'
                 WHEN abs(coalesce(amt,0.0)) >= 1000     THEN toString(round(amt/1000.0, 2))     + ' Thousand tk'
                 ELSE toString(round(coalesce(amt,0.0), 2)) + ' tk'
               END;


// ---------------------------------------------------------------------
// 3.10 Level 10 - the counterparty customers, "Customer-<TXN_WITH_ACC>".
//
//      THE BALANCING RULE. Counterparties come out biggest-first and the
//      running total is accumulated as we go. The expansion stops at the
//      first counterparty whose cumulative total covers this transaction
//      type's amount - the point at which the side being drilled into
//      balances against what moved through the type. Nothing past that
//      point adds anything, so it is not drawn, and an END node closes
//      the branch.
//
//      `cut` is the index of that stopping point: the first i where
//      sum(rows[0..i]) >= the type amount.
//
//      WHY THERE IS AN "Others" NODE. The balance point can sit past
//      `max_counterparties` - one transaction type in this dataset has
//      2,259 distinct counterparties, and drawing them all would be a
//      fan-out no browser or human can read. So the tail past the cap is
//      rolled into ONE "Others (n customers)" node carrying exactly the
//      remaining amount. The branch still balances to the last paisa;
//      it just does it in a readable number of nodes.
//
//      Relationship caption = amount moved with that counterparty.
// ---------------------------------------------------------------------
MATCH (n:Nav:TxnTypeNode)
// the full picture: every counterparty, uncapped, for the balance maths
CALL {
  WITH n
  MATCH (t:Transaction)
  WHERE t.stmt_acc = n.acc
    AND t.txn_type_d_c = n.dc
    AND t.txn_type = n.txn_type
    AND t.with_acc IS NOT NULL AND t.with_acc <> ''
  RETURN sum(t.amount)             AS cp_total,
         count(DISTINCT t.with_acc) AS cp_count
}
// the capped, ordered head: the ones actually drawn
CALL {
  WITH n
  MATCH (t:Transaction)
  WHERE t.stmt_acc = n.acc
    AND t.txn_type_d_c = n.dc
    AND t.txn_type = n.txn_type
    AND t.with_acc IS NOT NULL AND t.with_acc <> ''
  WITH t.with_acc AS cp, sum(t.amount) AS amt, count(t) AS cnt
  ORDER BY amt DESC, cp ASC
  LIMIT $max_counterparties
  RETURN collect({cp: cp, amt: amt, cnt: cnt}) AS rows
}
WITH n, cp_total, cp_count, rows
WHERE size(rows) > 0
WITH n, cp_total, cp_count, rows,
     [i IN range(0, size(rows) - 1)
        WHERE reduce(s = 0.0, j IN range(0, i) | s + rows[j].amt) >= coalesce(n.amount, 0.0) - 0.01
      | i] AS covered
WITH n, cp_total, cp_count, rows,
     CASE WHEN size(covered) = 0 THEN size(rows) - 1 ELSE covered[0] END AS cut
WITH n, cp_total, cp_count, rows[0..cut + 1] AS shown
WITH n, cp_total, cp_count, shown,
     reduce(s = 0.0, x IN shown | s + x.amt) AS reached

// ... the counterparty nodes themselves
CALL {
  WITH n, shown
  UNWIND range(0, size(shown) - 1) AS i
  WITH n, i, shown[i].cp AS cp, shown[i].amt AS amt, shown[i].cnt AS cnt
  MERGE (r:Nav:CounterpartyNode {key: 'cp:' + n.key + ':' + cp})
  SET r.name         = 'Customer-' + cp,
      r.acc          = n.acc,
      r.counterparty = cp,
      r.txn_type     = n.txn_type,
      r.dc           = n.dc,
      r.rank         = i + 1,
      r.level        = 10,
      r.path         = n.path + 'cp:' + cp + '/',
      r.parent_key   = n.key,
      r.click        = 'cp:' + n.key + ':' + cp,
      r.amount       = amt,
      r.txn_count    = cnt,
      r.f_acc        = n.acc,
      r.f_dc         = n.dc,
      r.f_type       = n.txn_type,
      r.f_cp         = cp
  MERGE (n)-[e:EXPANDS]->(r)
  SET e.amount = amt,
      e.name   = CASE
                   WHEN abs(coalesce(amt,0.0)) >= 10000000 THEN toString(round(amt/10000000.0, 2)) + ' Crore tk'
                   WHEN abs(coalesce(amt,0.0)) >= 100000   THEN toString(round(amt/100000.0, 2))   + ' Lakh tk'
                   WHEN abs(coalesce(amt,0.0)) >= 1000     THEN toString(round(amt/1000.0, 2))     + ' Thousand tk'
                   ELSE toString(round(coalesce(amt,0.0), 2)) + ' tk'
                 END
  RETURN count(*) AS made
}

// ... the "Others" rollup, ONLY when the cap cut the tail short
CALL {
  WITH n, cp_total, cp_count, shown, reached
  WITH n, cp_count - size(shown) AS others_cnt, cp_total - reached AS others_amt
  WHERE others_cnt > 0
  MERGE (o:Nav:OthersNode {key: 'others:' + n.key})
  SET o.name       = 'Others (' + toString(others_cnt) + ' customers)',
      o.acc        = n.acc,
      o.txn_type   = n.txn_type,
      o.dc         = n.dc,
      o.level      = 10,
      o.path       = n.path + 'others/',
      o.parent_key = n.key,
      o.click      = 'others:' + n.key,
      o.amount     = others_amt,
      o.cp_count   = others_cnt,
      o.f_acc      = n.acc,
      o.f_dc       = n.dc,
      o.f_type     = n.txn_type,
      o.f_cp       = null
  MERGE (n)-[e:EXPANDS]->(o)
  SET e.amount = others_amt,
      e.name   = CASE
                   WHEN abs(coalesce(others_amt,0.0)) >= 10000000 THEN toString(round(others_amt/10000000.0, 2)) + ' Crore tk'
                   WHEN abs(coalesce(others_amt,0.0)) >= 100000   THEN toString(round(others_amt/100000.0, 2))   + ' Lakh tk'
                   WHEN abs(coalesce(others_amt,0.0)) >= 1000     THEN toString(round(others_amt/1000.0, 2))     + ' Thousand tk'
                   ELSE toString(round(coalesce(others_amt,0.0), 2)) + ' tk'
                 END
  RETURN count(*) AS made_others
}

// ... and the END node that closes the branch.
//     `covered` is everything drawn under this type, Others included, so
//     it equals cp_total whenever the tail was rolled up. Anything still
//     missing is debits that carry no TXN_WITH_ACC at all - real gaps in
//     the source, not something the expansion dropped, and the END node
//     names that amount rather than hiding it.
WITH n, shown, cp_total, cp_count, reached,
     CASE WHEN cp_count > size(shown) THEN cp_total ELSE reached END AS covered,
     coalesce(n.amount, 0.0) AS target
MERGE (z:Nav:EndNode {key: 'end:' + n.key})
SET z.name         = CASE WHEN covered >= target - 0.01
                          THEN 'END'
                          ELSE 'END (no counterparty on remainder)' END,
    z.acc          = n.acc,
    z.txn_type     = n.txn_type,
    z.dc           = n.dc,
    z.level        = 10,
    z.path         = n.path + 'end/',
    z.parent_key   = n.key,
    z.click        = 'root',           // <-- END cycles back to Pathao Pay
    z.covered      = covered,
    z.target       = target,
    z.remaining    = target - covered,
    z.shown_count  = size(shown),
    z.rolled_up    = cp_count - size(shown),
    z.balanced     = covered >= target - 0.01,
    z.f_acc        = n.acc,
    z.f_dc         = n.dc,
    z.f_type       = n.txn_type,
    z.f_cp         = null
MERGE (n)-[e:EXPANDS]->(z)
SET e.amount = covered,
    e.name   = CASE WHEN covered >= target - 0.01
                    THEN 'balanced'
                    ELSE 'no counterparty on ' + CASE
                           WHEN abs(target - covered) >= 10000000 THEN toString(round((target - covered)/10000000.0, 2)) + ' Crore tk'
                           WHEN abs(target - covered) >= 100000   THEN toString(round((target - covered)/100000.0, 2))   + ' Lakh tk'
                           WHEN abs(target - covered) >= 1000     THEN toString(round((target - covered)/1000.0, 2))     + ' Thousand tk'
                           ELSE toString(round(target - covered, 2)) + ' tk'
                         END
               END;

// ---------------------------------------------------------------------
// 3.11 Report - node counts per level
// ---------------------------------------------------------------------
MATCH (n:Nav)
RETURN n.level AS level,
       [l IN labels(n) WHERE l <> 'Nav'][0] AS node_type,
       count(*) AS nodes
ORDER BY level, node_type;
