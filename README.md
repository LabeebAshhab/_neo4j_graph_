# KGN4j — PostgreSQL ➜ Neo4j ➜ NeoDash transaction flow

Loads a transaction statement CSV into PostgreSQL (via pgAdmin), pulls it into
Neo4j Community, and explores it in **real NeoDash** — a data table and a graph
side by side, where the graph is a **Pathao Pay drill-down that expands one
level per click** and cycles back to the start from the deepest level.

No custom UI. Stock NeoDash, stock Neo4j Community, stock pgAdmin.

```
  CSV --(pgAdmin import)--> PostgreSQL  stmt.txn_stage --> stmt.transactions
                                              |
                                     stmt.v_txn_for_graph  (view)
                                              |
                                      apoc.load.jdbc (JDBC)
                                              v
                              Neo4j Community  (Account / Transaction)
                                              |
                              precomputed :Nav drill-down tree
                                              v
                        NeoDash (node.js, http://localhost:3000)
                        graph card  +  table card, side by side
```

---

## 1. What's in here

| Path | What it is |
|---|---|
| `sql/01_schema.sql` | staging + typed tables, tolerant date/number parsers |
| `sql/02_load_csv.sql` | CSV import instructions, stage ➜ typed conversion, sanity checks |
| `sql/03_view_for_neo4j.sql` | the two views Neo4j reads over JDBC |
| `cypher/01_constraints.cypher` | constraints and indexes |
| `cypher/02_load_from_postgres.cypher` | `apoc.load.jdbc` ingest into the graph |
| `cypher/02b_load_from_csv.cypher` | CSV-export ingest, for Neo4j versions without `apoc.load.jdbc` |
| `cypher/03_build_nav_graph.cypher` | builds the Pathao Pay drill-down tree |
| `cypher/04_verify.cypher` | checks, including a simulation of the dashboard query |
| `cypher/legacy/` | the superseded linear debit-chain builder, kept for reference |
| `cypher/neodash/*.cypher` | the exact query for each dashboard card |
| `dashboards/kgn4j-dashboard.json` | the NeoDash dashboard, ready to import |
| `config/apoc.conf.sample` | the JDBC connection string Neo4j needs |
| `config/neo4j.conf.snippet` | the security settings APOC needs |
| `scripts/setup-neodash.ps1` | clone + `npm install` + `npm run dev` |
| `scripts/check-prereqs.ps1` | verifies ports and tooling before you start |
| `data/sample_transactions.csv` | 17 rows in your exact column layout, for testing |
| `docs/RUNBOOK.md` | **start here to run it** — step-by-step with this machine's real paths |
| `docs/DATA_MODEL.md` | the graph model and why the chain is precomputed |
| `docs/NEODASH_CARDS.md` | wiring each card by hand in the NeoDash UI |
| `docs/TROUBLESHOOTING.md` | the errors you will actually hit |
| `docs/SUSPECT_NETWORK.md` | **separate pipeline**: the suspected-wallet sheet → `cypher/suspect/` → `dashboards/kgn4j-dashboard-suspect.json` |

---

## 2. Prerequisites

| Component | Version | Note |
|---|---|---|
| PostgreSQL | 14+ | `FILTER (WHERE ...)` aggregates are used |
| pgAdmin | 4.x | the CSV import UI |
| Neo4j Community | 5.x or 2025.x/2026.x | Desktop or the zip distribution |
| APOC | matching Neo4j | **Version-sensitive — read this.** `apoc.load.jdbc` is in APOC **Core** on 5.x, but on 2025.x/2026.x it lives in APOC **Extended**, which is published separately and lags Core. Verified on 2026.08.1: Core contains only `load.json`, `load.xml`, `load.csv`, `load.arrow` — no `load.jdbc`. See `docs/TROUBLESHOOTING.md`. |
| PostgreSQL JDBC driver | 42.7.x | `postgresql-42.7.x.jar` |
| Node.js | 18 or 20 LTS | for NeoDash; newer usually works, but LTS is the safe pick |
| Git | any | to clone NeoDash |

Run `.\scripts\check-prereqs.ps1` to confirm the ports are up.

**To actually run this, follow [`docs/RUNBOOK.md`](docs/RUNBOOK.md)** — it has the
commands with your installed paths already filled in. The sections below
explain each stage in general terms.

---

## 3. PostgreSQL / pgAdmin

1. In pgAdmin, create the database:
   ```sql
   CREATE DATABASE kgn4j;
   ```
2. Open the Query Tool **on `kgn4j`** and run `sql/01_schema.sql`.
3. Import the CSV into the staging table:
   - browser tree → `kgn4j` → *Schemas* → `stmt` → *Tables* → `txn_stage`
   - right click → **Import/Export Data...** → **Import**
   - *Filename*: your CSV (start with `data\sample_transactions.csv`)
   - *Format* `csv`, *Encoding* `UTF8`, *Header* **Yes**, *Delimiter* `,`
   - **Columns** tab: keep all 17, in file order
   - OK
4. Run `sql/02_load_csv.sql` — this converts staging ➜ `stmt.transactions`
   and prints per-account debit/credit totals. Check that the last query returns
   **no rows**; anything there failed to parse.
5. Run `sql/03_view_for_neo4j.sql`.

The staging-table detour exists because statement exports carry inconsistent
date formats and thousand separators. `stmt.safe_ts()` tries eleven date
formats and `stmt.safe_num()` strips anything that isn't a digit, dot or minus,
so a malformed row lands in the table instead of aborting the whole import.

---

## 4. Neo4j Community

1. **Drop in the drivers.** Copy into `<NEO4J_HOME>\plugins\`:
   - `apoc-5.x.x-core.jar` (Neo4j Desktop: the *APOC* plugin install button)
   - `postgresql-42.7.x.jar` — download from https://jdbc.postgresql.org/download/

2. **Configure.** Append `config/neo4j.conf.snippet` to `<NEO4J_HOME>\conf\neo4j.conf`,
   then copy `config/apoc.conf.sample` to `<NEO4J_HOME>\conf\apoc.conf` and put your
   real PostgreSQL password in it:
   ```properties
   apoc.jdbc.pg.url=jdbc:postgresql://localhost:5432/kgn4j?user=postgres&password=YOUR_PASSWORD
   ```
   In Neo4j Desktop both files are behind **... → Open Folder → Configuration**.

3. **Restart Neo4j.** Config changes are read at startup only.

4. **Smoke-test the link** in Neo4j Browser (http://localhost:7474):
   ```cypher
   CALL apoc.load.jdbc('pg','SELECT count(*) AS n FROM stmt.v_txn_for_graph')
   YIELD row RETURN row;
   ```
   A number here means the whole PostgreSQL ➜ Neo4j path works. If it errors,
   go to `docs/TROUBLESHOOTING.md` before doing anything else.

5. **Build the graph**, in order:
   ```
   cypher/01_constraints.cypher
   cypher/02_load_from_postgres.cypher     <- starts with MATCH (n) DETACH DELETE n
   cypher/03_build_flow_chain.cypher
   cypher/04_verify.cypher
   ```
   Every account in check 4.2 should show `chain_length > 0` and
   `final_cumulative == debit_on_graph`.

---

## 5. NeoDash

```powershell
.\scripts\setup-neodash.ps1
```

Clones https://github.com/neo4j-labs/neodash, runs `npm install`, then
`npm run dev`. Open http://localhost:3000.

Or by hand:

```bash
git clone https://github.com/neo4j-labs/neodash.git
cd neodash
npm install --legacy-peer-deps
npx webpack-dev-server --mode development
```

NeoDash's own `dev` script is `yarn webpack-dev-server ...`, so `npm run dev`
fails with *"yarn is not recognized"* unless you have yarn. Calling
`webpack-dev-server` directly is the same server on the same port.
`scripts/setup-neodash.ps1` detects this and picks the right one.

**Connect:** Protocol `neo4j://` (or `bolt://`), Host `localhost`, Port `7687`,
Database `neo4j`, plus your Neo4j username and password.

**Load the dashboard:** menu (top left) → **Load Dashboard** → **Select from file**
→ `dashboards\kgn4j-dashboard.json` → *Load Dashboard*.

> The dashboard JSON includes the click-to-parameter *action rules*. NeoDash's
> action extension must be enabled for them to fire: menu → **Extensions** →
> turn on **Report Actions**. If a click does nothing after that, the rule
> didn't survive the import — `docs/NEODASH_CARDS.md` has the 60-second UI
> recipe to add it back. Everything else about the dashboard is unaffected.

---

## 6. How the interaction works

The graph card opens on **Pathao Pay**. Every click reveals exactly one more
level, and clicking the END node at the bottom returns you to the top:

```
Pathao Pay
   -> Customers 1-10 of 380              edge = total credited to customers
       |   click it again for 11-20, 21-30, ... wrapping at the end
       -> C1 / C2 / C3 ... C10           edge = that customer's credited amount
           -> Customer-<STATEMENT_FOR_ACC>   edge = total debit + credit
               -> TXN_TYPE_D_C               edge = total debit + credit
                   -> Credit                 edge = credited
                   |   -> P2P / TOP UP / CASH OUT / ...   edge = amount
                   |       -> Customer-<TXN_WITH_ACC>     edge = amount
                   |       -> END
                   -> Debit                  edge = debited
                       -> TXN_TYPE           edge = debited
                           -> P2P / TOP UP / CASH OUT / ...  edge = amount
                               -> Customer-<TXN_WITH_ACC>    edge = amount
                               -> END  -> click cycles back to Pathao Pay
```

Relationship captions are short-form Bangladeshi notation — `138.29 Crore tk`
for `1382920243.4999224`, and the same for Lakh and Thousand. The exact value
stays on the relationship as `amount`, so hover still gives the real figure.

The bottom level stops expanding at the point where the counterparty amounts
cover the transaction type's total — where the branch balances — and closes
with an **END** node. When balancing would need more than `max_counterparties`
nodes, the tail collapses into one **Others (n customers)** node carrying the
exact remainder, so totals reconcile without an unreadable fan-out.

Every `:Nav` node carries a materialized `path`, a `parent_key` and a `click`
property. Clicking writes `click` into the `neodash_focus` parameter; the card's
query then shows the focus node, its breadcrumb back to Pathao Pay, and its
direct children. On END nodes `click` is `'root'` — one property set
differently is the whole cycle.

Each node also carries four filter properties — `f_acc`, `f_dc`, `f_type`,
`f_cp` — mapping to `STATEMENT_FOR_ACC`, `TXN_TYPE_D_C`, `TXN_TYPE` and
`TXN_WITH_ACC`. The transactions table applies whichever are set on the node
in focus, so the dataframe always matches the selection: a customer node
gives that customer's rows, **CASH OUT** gives only their cash-outs, and a
bottom-level `Customer-…` node gives only the rows between those two accounts.

The table card shows all 17 source columns and narrows to the customer
currently in focus, so both cards stay in step. `docs/DATA_MODEL.md` has the
full node/edge table.

---

## 7. Rebuilding after new data

```
pgAdmin : TRUNCATE stmt.txn_stage;  then re-import the CSV
pgAdmin : run sql/02_load_csv.sql
Neo4j   : run cypher/02_load_from_postgres.cypher, then cypher/03_build_flow_chain.cypher
NeoDash : refresh the browser tab (the reload icon on a card re-runs just that card)
```

Both Cypher scripts are idempotent — `02` wipes the graph first, `03` drops and
rebuilds the chain.

---

## 8. One assumption worth knowing

Your description — *"it will show me all the transactions that occur with other
accounts until the credited amount sums up to the debited amount"* — is
implemented as: **the chain walks the selected account's own outgoing (`D`)
transactions in time order, and each step's running total is compared against
the account's total debited amount.** The chain therefore always terminates
exactly on the debited figure, which is what `cypher/04_verify.cypher` §4.2
asserts.

If you actually meant tracing the money *onward* — the counterparty's own
onward debits, then theirs, hop after hop — the graph already holds that
(`(:Account)-[:DEBITED]->(:Transaction)-[:CREDITED]->(:Account)` is a full
money-flow network); only `cypher/03` changes. `docs/DATA_MODEL.md` sketches
that variant.
