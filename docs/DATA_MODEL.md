# Graph data model

Two layers, deliberately kept apart: **the facts** (what the statement says)
and **the walk** (what the dashboard expands).

## Layer 1 — facts

```
(:Account {acc_no})
   -[:DEBITED]-> (:Transaction {row_key, txn_id, txn_type, amount, ...}) -[:CREDITED]-> (:Account)
```

One `Transaction` node per **row** of the source table, keyed on `row_key`.
`from_acc` / `to_acc` are derived from `TXN_TYPE_D_C` in the SQL view, so the
relationship always points the way the money moved regardless of whose
statement the row came from.

Built by `cypher/02_load_from_postgres.cypher` (JDBC) or
`cypher/02b_load_from_csv.cypher` (CSV export). Identical result either way.

## Layer 2 — the Pathao Pay drill-down

A navigation tree of `:Nav` nodes joined by `:EXPANDS`, built by
`cypher/03_build_nav_graph.cypher`.

| level | label | one per | caption | edge caption from parent |
|---|---|---|---|---|
| 1 | `Provider` | the platform | "Pathao Pay" | total credited to customers |
| 2 | `CustomerPage` | page of 10 customers | "Customers 1-10 of 380" | that customer's credited amount |
| 3 | `Customer` | customer credited | "C1", "C2", … "Cn" | total debit + credit |
| 4 | `CustomerAcc` | customer | "Customer-\<STATEMENT_FOR_ACC\>" | total debit + credit |
| 5 | `TxnTypeDC` | customer | "TXN_TYPE_D_C" | credited / debited |
| 6 | `CreditNode` | customer | "Credit" | amount per type |
| 7 | `DebitNode` | customer | "Debit" | debited total |
| 8 | `TxnTypeHub` | customer | "TXN_TYPE" | amount per type |
| 9 | `TxnTypeNode` | customer × D/C × TXN_TYPE | "P2P", "CASH OUT", … | amount with that counterparty |
| 10 | `CounterpartyNode` | customer × D/C × type × counterparty | "Customer-\<TXN_WITH_ACC\>" | amount moved with them |
| 10 | `OthersNode` | type branch that overran the cap | "Others (n customers)" | the remainder |
| 10 | `EndNode` | type branch | "END" | "balanced" |

`Customer` nodes are numbered by credited amount, highest first, so C1 is the
largest customer. The account number itself appears one level down, on the
`CustomerAcc` node — click C2 and "Customer-3827837287" opens beside it.

`Credit` expands straight into its transaction types; `Debit` goes through the
extra `TxnTypeHub` node first. `TxnTypeNode` carries a `dc` property that keeps
the two sides apart, which is why its key includes `:C:` or `:D:`.

Every node also carries the `Nav` label, so the dashboard can match the whole
tree with `MATCH (n:Nav)` while NeoDash still colours by the specific label.

### Relationship captions

Every `:EXPANDS` relationship carries the exact figure on `amount` and a short
Bangladeshi-notation caption on `name`:

| raw amount | caption |
|---|---|
| `1382920243.4999224` | `138.29 Crore tk` |
| `2936293.9272249998` | `29.36 Lakh tk` |
| `70824.7` | `708.25 Thousand tk` |
| `512.4` | `512.4 tk` |

Cutovers are 1 Crore = 10,000,000 · 1 Lakh = 100,000 · 1 Thousand = 1,000.
Hover a relationship in NeoDash to see the exact `amount`.

### Node properties that drive the dashboard

| property | purpose |
|---|---|
| `key` | unique id, e.g. `type:5631809894:D:P2P` |
| `path` | materialized path with trailing slash, e.g. `/root/cpage:2/cust:X/acc/dc/debit/types/type:P2P/` |
| `parent_key` | the node one level up |
| `click` | **the key to focus when this node is clicked** |
| `name` | the caption NeoDash renders |
| `level` | depth, for ordering and diagnostics |
| `f_acc` `f_dc` `f_type` `f_cp` | **the table filter** — see below |

### The table filter

The transactions card is dynamic: it reads four properties off whichever node
is in focus and applies whichever are set.

| property | column | set from |
|---|---|---|
| `f_acc` | `STATEMENT_FOR_ACC` | level 3 (C1…Cn) downwards |
| `f_dc` | `TXN_TYPE_D_C` | level 6/7 (Credit / Debit) downwards |
| `f_type` | `TXN_TYPE` | level 9 (P2P, CASH OUT, …) downwards |
| `f_cp` | `TXN_WITH_ACC` | level 10 counterparty nodes only |

All four null on Pathao Pay and the Customers pages, so the table shows a
sample of everything. Each level down narrows it further, and the breadcrumb card prints
the filter in force so it is never a guess why the dataframe holds what it does.

## The reveal rule

```cypher
WITH coalesce($neodash_focus, 'root') AS fk
MATCH (f:Nav {key: fk})
MATCH (n:Nav)
WHERE f.path STARTS WITH n.path      // ancestors + the focus itself
   OR (n.parent_key = f.key          // the focus node's direct children ...
       AND (NOT n:CustomerPage OR n.page = 1))   // ... but only page 1
```

Show the focus, its breadcrumb back to Pathao Pay, and one level of children.
One click reveals exactly one level.

### Paging level 2

380 customers on screen at once is unreadable, so level 2 is cut into pages of
`page_size` (default 10). Each page is a `CustomerPage` node captioned
"Customers 1-10 of 380", holding its own ten `Customer` children, and its
`click` points at the **next** page — so clicking the Customers node again
swaps in the next ten, wrapping to the first page at the end.

All 38 pages hang off the root, which would fan Pathao Pay out into 38
near-identical nodes. The `n.page = 1` clause above is what prevents that:
only page 1 is ever revealed automatically, and pages 2+ are reachable only by
clicking. The level therefore behaves like one node cycling through tens, and
the graph stays at constant depth — twelve nodes on screen at any page.

The first version of this project used a linear `step <= depth + 1` counter.
That cannot work here: this tree **branches** (Credit and Debit, then many
transaction types, then many counterparties), and a single integer can't say
*which* branch you're in. Materialized paths handle branching for free, and the
trailing slash on every path is what stops `cust:1` matching `cust:10`.

## Where the bottom level stops

Under a `TxnTypeNode`, counterparties are emitted highest-amount-first and the
running total accumulated as it goes. The expansion stops at the first
counterparty whose cumulative total covers the type's amount — the point where
that branch balances — and an `EndNode` closes it. Nothing past that point adds
anything to the total, so it is not drawn.

That balance point can sit past `max_counterparties`. One transaction type in
this dataset has 2,259 distinct counterparties, and drawing them all is a
fan-out no browser or reader can use. So the tail past the cap collapses into a
single `OthersNode` holding exactly the remaining amount. The branch still
balances to the last paisa; it just does it in a readable number of nodes —
across the whole graph, 18 nodes per branch on average and never more than 101.

`cypher/04_verify.cypher` §4.7 checks this: the counterparty edges plus the
Others edge must equal the type's amount for every branch. Anything that does
not balance is a transaction carrying no `TXN_WITH_ACC` in the source, and the
END node names that amount rather than hiding it.

## The cycle

`click` normally equals the node's own `key`. On `EndNode` it is `'root'`.
NeoDash writes whatever `click` holds into the `focus` parameter, so clicking
END jumps the focus back to Pathao Pay and the graph collapses to the start.
The cycle needs no special case in the dashboard — it falls out of one
property set differently on one label.

## Configuring who counts as a Pathao Pay customer

At the top of `cypher/03_build_nav_graph.cypher`:

```cypher
:param pathao_name => 'Pathao Pay';
:param pathao_acc  => null;
```

- `pathao_acc = null` — every credit on a customer statement counts as coming
  from the platform. Correct when the export is Pathao Pay's own book.
- `pathao_acc = '<account>'` — only credits whose `TXN_WITH_ACC` equals that
  account count. Use this when the export mixes several sources and only one
  settlement account is Pathao Pay.

Nothing else in the file needs editing to switch between the two.

## Rebuilding

`cypher/03` starts with `MATCH (n:Nav) DETACH DELETE n`, so it is re-runnable
and never touches `:Transaction` or `:Account`. Re-run it after changing
`pathao_acc` or reloading the source data.
