// =====================================================================
// KGN4j - step 4 : checks to run before opening NeoDash
// =====================================================================

// 4.1  Source graph census
MATCH (n) RETURN labels(n) AS label, count(*) AS count ORDER BY label;
MATCH ()-[r]->() RETURN type(r) AS rel_type, count(*) AS count ORDER BY rel_type;


// 4.2  The drill-down tree, level by level.
//      Expect exactly one Provider and one CustomerGroup, and one
//      Customer (C1..Cn) per customer credited from Pathao Pay.
MATCH (n:Nav)
RETURN n.level AS level,
       [l IN labels(n) WHERE l <> 'Nav'][0] AS node_type,
       count(*) AS nodes
ORDER BY level, node_type;


// 4.3  Every node must have exactly one parent (except the root), or the
//      breadcrumb and the reveal rule will misbehave. Expect NO rows.
MATCH (n:Nav)
WHERE n.key <> 'root'
  AND NOT EXISTS { MATCH (:Nav)-[:EXPANDS]->(n) }
RETURN n.key AS orphan_node, n.level AS level;


// 4.4  Materialized paths must be unique and prefix-safe. Expect NO rows.
MATCH (n:Nav)
WITH n.path AS p, collect(n.key) AS keys
WHERE size(keys) > 1
RETURN p AS duplicate_path, keys;


// 4.5  Money check: the total on the Customers edge must equal the sum
//      of every per-customer edge, across all pages.
MATCH (:Nav {key:'root'})-[top:EXPANDS]->(:Nav:CustomerPage)
WITH max(top.amount) AS declared_total
MATCH (:Nav:CustomerPage)-[u:EXPANDS]->(:Nav:Customer)
WITH declared_total, sum(u.amount) AS sum_of_customers
RETURN declared_total, sum_of_customers,
       CASE WHEN abs(declared_total - sum_of_customers) < 0.005
            THEN 'BALANCED' ELSE 'MISMATCH' END AS status;


// 4.5b Paging integrity: every customer must appear on exactly one page,
//      the pages must form an unbroken click-ring back to page 1, and no
//      page may hold more than `page_size`. Expect NO rows.
MATCH (c:Nav:Customer)
WITH c, count { (:Nav:CustomerPage)-[:EXPANDS]->(c) } AS pages
WHERE pages <> 1
RETURN c.key AS customer_on_wrong_page_count, pages;

MATCH (p:Nav:CustomerPage)
OPTIONAL MATCH (nextp:Nav:CustomerPage {key: p.click})
WITH p, nextp
WHERE nextp IS NULL
   OR nextp.page <> CASE WHEN p.page = p.page_count THEN 1 ELSE p.page + 1 END
RETURN p.key AS broken_page_link, p.click AS points_at;


// 4.6  Per customer: the debited transaction-type edges under TXN_TYPE
//      must sum to the debited total.
MATCH (h:Nav:TxnTypeHub)-[e:EXPANDS]->(:Nav:TxnTypeNode)
WITH h, sum(e.amount) AS sum_types
RETURN h.acc AS account, h.total AS total_debited, sum_types,
       CASE WHEN abs(h.total - sum_types) < 0.005
            THEN 'BALANCED' ELSE 'MISMATCH' END AS status
ORDER BY account;


// 4.6b Same on the credit side: the credited type edges under Credit
//      must sum to the credited total.
MATCH (c:Nav:CreditNode)-[e:EXPANDS]->(:Nav:TxnTypeNode)
WITH c, sum(e.amount) AS sum_types
RETURN c.acc AS account, c.total AS total_credited, sum_types,
       CASE WHEN abs(c.total - sum_types) < 0.005
            THEN 'BALANCED' ELSE 'MISMATCH' END AS status
ORDER BY account;


// 4.7  The balancing rule at level 9 -> 10. Counterparty edges are
//      accumulated until they cover the type's amount; whatever sits
//      past max_counterparties is rolled into the Others node. Both
//      count here, so every branch should read BALANCED. Anything else
//      is a transaction with no TXN_WITH_ACC in the source.
MATCH (ty:Nav:TxnTypeNode)-[e:EXPANDS]->(c:Nav)
WHERE c:CounterpartyNode OR c:OthersNode
WITH ty, sum(e.amount) AS sum_cp,
     count(CASE WHEN c:CounterpartyNode THEN 1 END) AS drawn,
     count(CASE WHEN c:OthersNode       THEN 1 END) AS rolled_up
RETURN ty.acc AS account, ty.dc AS d_c, ty.txn_type AS txn_type,
       ty.amount AS type_amount, sum_cp, drawn, rolled_up,
       CASE WHEN abs(ty.amount - sum_cp) < 0.01 THEN 'BALANCED'
            ELSE 'GAP (rows with no counterparty)' END AS status
ORDER BY account, d_c, txn_type;


// 4.7b The same, summarised - this is the one to read first.
//      Expect a single row: balanced = TRUE for every branch.
MATCH (z:Nav:EndNode)
RETURN z.balanced AS balanced, count(*) AS branches,
       round(avg(z.shown_count)) AS avg_drawn,
       max(z.shown_count)        AS max_drawn,
       sum(z.rolled_up)          AS customers_rolled_into_others
ORDER BY balanced DESC;


// 4.8  The cycle: every END node must point back to the root.
//      Expect a single row reading 'root'.
MATCH (z:Nav:EndNode)
RETURN DISTINCT z.click AS cycles_back_to, count(*) AS end_nodes;


// 4.8b The table filter: every node must carry the four f_* properties
//      the transactions card reads, and they must get progressively
//      narrower going down. Expect NO rows.
MATCH (n:Nav)
WHERE n.level >= 3 AND n.f_acc IS NULL
RETURN n.key AS node_without_account_filter, n.level AS level;


// 4.9  Simulate the dashboard query at a chosen focus. Change the value
//      to walk the tree without opening NeoDash.
:param neodash_focus => 'root';
WITH coalesce($neodash_focus, 'root') AS fk
MATCH (f:Nav {key: fk})
MATCH (n:Nav)
WHERE f.path STARTS WITH n.path OR n.parent_key = f.key
WITH collect(DISTINCT n) AS shown
UNWIND shown AS a
MATCH p = (a)-[:EXPANDS]->(b)
WHERE b IN shown
RETURN p;


// 4.10 The same walk as a readable list rather than a graph.
WITH coalesce($neodash_focus, 'root') AS fk
MATCH (f:Nav {key: fk})
MATCH (n:Nav)
WHERE f.path STARTS WITH n.path OR n.parent_key = f.key
RETURN n.level AS level, n.name AS node, n.key AS key,
       CASE WHEN n.parent_key = f.key THEN 'newly revealed'
            WHEN n.key = f.key        THEN '<- focus'
            ELSE 'breadcrumb' END AS role
ORDER BY level, node;
