# Suspect Network — second pipeline

A separate pipeline and dashboard, `dashboards/kgn4j-dashboard-suspect.json`,
built from the suspected-wallet sheet (`Book1.xlsx`). **The original pipeline is
untouched**: the Pathao Pay drill-down (`cypher/02b`–`04`,
`kgn4j-dashboard.json`) and the Money Trail (`cypher/05`, `cypher/trace/`,
`kgn4j-dashboard-trail.json`) run exactly as before.

It stays apart in the database too: this pipeline only creates `:SusRow` (sheet
rows) and `:SNet` / `:SFLOW` (the drawn graph), and only ever deletes those. It
never reads or writes `:Transaction`, `:Account`, `:Nav` or `:Canon`.

## The graph

Every node has two captions:

| property | drawn | example |
|---|---|---|
| `name` | inside the circle | `Agent`, `1872`, `90 Cr` |
| `outer` | outside, to the right | `01979603374`, `Suspended` |

```
LAYERS 1-3  STATIC (typed in from the hand notes)

(Agent) 01979603374 --Cash IN 5090--> (TR) 01333157844 --P2P 5085--> (Customer) 01961932548
(Customer) --total TXN Wallet--> (1872)
(1872) --Merchant--> (1)    Suspended
       --Agent-----> (1082) --> (312) Active
                            --> (770) Suspended
       --Customer--> (789)  --> (340) Suspended
                            --> (441) Active
                            --> (8)   Deleted
                            --TXN_AMOUNT--> (90 Cr)

LAYERS 4-5  COMPUTED from the sheet

(90 Cr)  --txn_with_wallet--> (84930) Wallet        distinct TXN_WITH_ACC
(84930)  --90.44 Crore tk---> (789)                  total TXN_AMOUNT
(789)    --txn_type---------> (32) TXN_TYPE          distinct TXN_TYPE
(32)     --<amount>---------> (<wallets>) P2P / CASH OUT / CASH IN / ...
```

The 84930 Wallet node also breaks down by account type and status. This part
is **static**, typed in from the ACCOUNT_TYPE / STATUS / WALLET_COUNT table
(section 3.3b of `cypher/suspect/02`; edit the numbers there):

```
(84930) --Customer--> (60131) --> (55545) ACTIVE, (95) PRELIMINARY_ACCOUNT,
                                  (52) DELETED, (4439) SUSPENDED
        --Merchant--> (533)   --> (237) SUSPENDED, (296) ACTIVE
        --Uddokta---> (25218) --> (18034) SUSPENDED, (7184) ACTIVE
```

The group totals are the sums of their statuses. Together they come to 85,882,
which is 952 more than the 84,930 distinct TXN_WITH_ACC in the sheet. The
table is drawn as given.

For each transaction type the number inside is how many distinct
`TXN_WITH_ACC` wallets used it, the type name is outside, and the edge carries
the amount. The top 10 types by amount are drawn (`:param top_types` in
`cypher/suspect/02`), and the other 22 are rolled into one `Others (22 types)`
node, so the edges still add up to exactly 90.44 Crore.

The sheet matches the notes: 90.44 Crore total, 84,930 distinct
`TXN_WITH_ACC`, and 781 distinct `SUSPECTED_WALLET` (= 789 − 8 deleted).

Every node is pinned to a fixed position (`pin_x` / `pin_y`, set in
`cypher/suspect/02`) laid out like the hand drawing. Edit those numbers to move
a node. `x` grows to the right and `y` grows *down*. Keep them **floats**
(`toFloat(...)` or `-70.0`): NeoDash converts negative Neo4j *integers*
wrongly (-230 becomes -4,294,967,526), which throws the node billions of units
away and shows up as an endless relationship line.

The graph fits itself to the card when it loads, text included. Scroll to
zoom, and drag to pan.

### Click to open the sheet rows in the graph (layers 6-7)

```
click P2P            -> (P2P) --amount--> (<cps>) 01971263087     top 10 suspected wallets
                                          ... + Others (n wallets)
click 01971263087    -> (01318024808) 4 --CREDIT 1.0 Lakh tk--> (wallet)   top 10 TXN_WITH_ACC
                        (wallet) --DEBIT ...--> (0171...) 2             + Others (n)
click any base node  -> collapses back to layers 1-5
```

* **Wallet node:** inside is the distinct TXN_WITH_ACC count, outside is
  SUSPECTED_WALLET, and the edge is the amount within that type.
* **Counterparty node:** inside is TXN_COUNT, outside is TXN_WITH_ACC, and the
  edge is `TXN_MODE amount`. The arrow follows the money: CREDIT (teal) points
  into the suspected wallet, DEBIT (tan) points out.
* Works for every type node, including `Others (22 types)`.
* At every level the child edges (Others included) add up exactly to the
  parent's amount.
* Adjust how many are shown with `:param top_wallets` /
  `:param top_counterparties` in `cypher/suspect/02`.

These nodes are prebuilt (121 wallet nodes and 598 counterparty nodes, built in
~8 s) and drawn only when their parent is on the clicked node's `chain`.

## The dashboard

* **Suspect network** (full width): the graph above. Clicks expand it as
  described, and the graph re-fits itself after each one.
* **Selected**: what was clicked and the filter the rows table is applying.
* **By TXN_TYPE (all types)**: every type, including the ones inside Others,
  with credit/debit split.
* **Sheet rows**: the source rows (top 2,000 by amount) behind the clicked
  node: type → wallet → counterparty + mode.

## Running it

```powershell
pip install openpyxl                                   # once
python scripts\export_suspect_csv.py                   # Book1.xlsx -> <neo4j>\import\suspect_wallet_txn.csv
```

Then in Neo4j Browser (or `cypher-shell -f`):

1. `cypher/suspect/01_load_suspect_rows.cypher`: loads 168,562 rows in ~15 s
2. `cypher/suspect/02_build_suspect_graph.cypher`: builds the 26-node graph

Then NeoDash → Load → paste `dashboards/kgn4j-dashboard-suspect.json`.
Regenerate that file with `python scripts\build_suspect_dashboard.py` after
editing any `cypher/suspect/cards/*.cypher`.

To use a different spreadsheet, pass its path:
`python scripts\export_suspect_csv.py D:\path\to\sheet.xlsx`, then re-run steps 1-2.

To remove the pipeline completely, run `cypher/suspect/99_undo_suspect.cypher`.

## NeoDash patch

Outside labels and fixed positions need `neodash-patches/kgn4j-suspect-graph.patch`,
which `scripts/setup-neodash.ps1` applies after `kgn4j-neodash.patch`. Both
features are opt-in. The outside label is drawn only when a card sets
"Outside label property", and a node is pinned only if it carries
`pin_x`/`pin_y`, which no other dashboard's nodes have. Without the patch the
dashboard still loads; the nodes just force-lay out and show only the inside
caption.
