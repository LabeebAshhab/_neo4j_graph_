# Building the cards by hand in NeoDash

Importing `dashboards/kgn4j-dashboard.json` should give you everything. Use
this page when a click-to-parameter *action rule* didn't survive the import, or
to rebuild a card from scratch.

Once per dashboard first: **menu (top left) → Extensions → enable
"Report Actions"**. Without it, clicking a graph node does nothing.

Parameter naming: in the UI you type the name **without** the `neodash_`
prefix; NeoDash adds it. In Cypher you write the full `$neodash_focus`.

The dashboard has three cards on one page, so the table and the graph are
visible at the same time:

```
+----------------------------------------------------------+
|  Where am I   (breadcrumb, full width)                    |
+---------------------------------+------------------------+
|  Pathao Pay drill-down (graph)  |  Transactions (table)   |
|                                 |                        |
+---------------------------------+------------------------+
```

---

## Card 1 — Where am I (Table)

- **Type**: `Table`
- **Query**: `cypher/neodash/card3_breadcrumb.cypher`
- **Settings**: *Compact* on

Shows the path from Pathao Pay down to whatever you last clicked, so you always
know where in the drill-down you are.

---

## Card 2 — Pathao Pay drill-down (Graph)

- **Type**: `Graph`
- **Query**: `cypher/neodash/card2_expansion_graph.cypher`
- **Settings**:
  - *Layout*: `tree` — a drill-down reads best top-down
  - *Show properties on hover*: on — how you read amounts and counts
  - *Node label font size*: ~3.2, *Relationship label font size*: ~3.0

**Captions.** In the card's property selector choose `name` for every node
label, and `name` for the `EXPANDS` relationship. The relationship `name` holds
the amount — that's what puts *200* on the P2P edge.

**The click rules** — Settings → **Actions** → add one rule per node label:

| Condition | Node label | Property | Action | Variable |
|---|---|---|---|---|
| `onNodeClick` | `Provider` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `CustomerPage` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `Customer` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `CustomerAcc` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `TxnTypeDC` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `CreditNode` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `DebitNode` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `TxnTypeHub` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `TxnTypeNode` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `CounterpartyNode` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `OthersNode` | `click` | `Set Variable` | `focus` |
| `onNodeClick` | `EndNode` | `click` | `Set Variable` | `focus` |

Every rule is identical: read the clicked node's `click` property into the
`focus` variable. Twelve rules only because NeoDash scopes a rule to one label.

Note the rule reads `click`, **not** `key`. They are the same value on every
label except `EndNode`, where `click` is `'root'` — that one difference is what
makes clicking END cycle back to the start.

> If your NeoDash build words these differently (`On node click`, `Node
> property`, `Set parameter`), the meaning is the same: condition, which label,
> which property to read, which parameter to write.

---

## Card 3 — Transactions (Table)

- **Type**: `Table`
- **Query**: `cypher/neodash/card1_transactions_table.cypher`
- **Settings**: *Compact* on, *Download CSV* on

All 17 source columns. The query is **dynamic**: it reads four filter
properties off whichever node is in focus and applies whichever are set.

| property | column filtered | set from |
|---|---|---|
| `f_acc` | `STATEMENT_FOR_ACC` | C1…Cn downwards (not the page node) |
| `f_dc` | `TXN_TYPE_D_C` | Credit / Debit downwards |
| `f_type` | `TXN_TYPE` | P2P, CASH OUT, … downwards |
| `f_cp` | `TXN_WITH_ACC` | the bottom-level Customer-… nodes |

So the table is never just "the customer you are inside": select **Debit** and
it holds only their debits, **CASH OUT** only their cash-outs, a bottom-level
`Customer-…` node only the rows between those two accounts. On Pathao Pay and
Customers all four are null, so it shows a sample of everything. Card 1 prints
the filter in force.

---

## Walking it

1. The graph opens on **Pathao Pay**.
2. Click it → **Customers 1-10 of 380**, edge captioned with the total
   credited (`990.84 Crore tk`).
3. Click that → **C1 … C10**, numbered by credited amount, each edge
   captioned with that amount. **Click the Customers node again** and it
   becomes *Customers 11-20 of 380* with C11 … C20 — ten per click, wrapping
   back to the first page at the end.
4. Click a customer → **Customer-\<account no\>**, the account number itself.
5. Click that → **TXN_TYPE_D_C**.
6. Click that → **Credit** and **Debit** side by side, edges captioned with
   the credited and debited totals.
7. **Credit** → its transaction types directly. **Debit** → **TXN_TYPE**, then
   its transaction types. Each edge captioned with the amount moved that way.
8. Click e.g. **P2P** → the counterparties as **Customer-\<account no\>**
   nodes, each edge captioned with the amount moved with them — plus an
   **END** node, and an **Others (n customers)** node where the tail was
   rolled up.
9. Click **END** → back to **Pathao Pay**.

---

## Saving your work

NeoDash keeps the dashboard in browser local storage. To keep edits:

- **menu → Save Dashboard → Download as JSON**, overwriting
  `dashboards/kgn4j-dashboard.json`, or
- **menu → Save Dashboard → Save to Neo4j**, which stores it as a
  `:_Neodash_Dashboard` node. Fine on Community.
