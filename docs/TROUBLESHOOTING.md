# Troubleshooting

## PostgreSQL / pgAdmin

**Import dialog: "extra data after last expected column"**
The CSV has more fields than `stmt.txn_stage` has columns, usually because a
`TXN_WITH_INFO` value contains an unquoted comma. Re-export with quoting, or
add a `"` *Quote* character in the import dialog's Options tab.

**`COPY` says "could not open file ... for reading"**
`COPY` runs on the PostgreSQL **server**, not in pgAdmin. Either put the file
somewhere the `postgres` service account can read, or use the Import/Export
dialog (which streams the file from your machine).

**Rows land with `txn_date_time` NULL**
`stmt.safe_ts()` didn't recognise the format. Look at a raw value:
```sql
SELECT DISTINCT txn_date_time FROM stmt.txn_stage LIMIT 20;
```
then add the format mask to the `formats` array in `sql/01_schema.sql` and
re-run `sql/02_load_csv.sql`.

**`txn_type_d_c` NULL**
The column holds something other than a `D…`/`C…` value — perhaps `DR`/`CR`
is fine (handled), but `1`/`2` or `OUT`/`IN` is not. Extend the `CASE` in
`sql/02_load_csv.sql`.

---

## Neo4j / APOC / JDBC

**`There is no procedure with the name apoc.load.jdbc`**
First check APOC is loaded at all — `CALL apoc.help('coll');` should return
rows. If other APOC procedures work but `load.jdbc` doesn't, APOC Core on your
version doesn't ship it.

**Verified on Neo4j 2026.08.1 (2026-09-21):** `apoc-2026.08.1-core.jar` contains
only `apoc/load/LoadJson`, `Xml`, `CSVResult` and `LoadArrow`. There is no
`Jdbc` class. `load.jdbc` is in APOC **Extended**, a separate download.

You can list what a jar actually contains without starting the server:

```bash
python -c "import zipfile;print([n for n in zipfile.ZipFile(r'C:\neo4j\neo4j-community-2026.08.1\plugins\apoc-2026.08.1-core.jar').namelist() if 'jdbc' in n.lower()])"
```

APOC Extended must match the server version closely. Extended's latest release
is **2026.04.0**; dropping that jar into a 2026.08.1 server makes Neo4j **fail
to start** with `ClassNotFoundException: com.ctc.wstx.io.InputBootstrapper`
(tested). If that happens, delete the extended jar from `plugins\` and restart
— the server recovers with no data loss.

Workable combinations:

| Neo4j | APOC Core | APOC Extended | `load.jdbc` |
|---|---|---|---|
| 5.26 LTS | 5.26.x | 5.26.4 | yes |
| 2026.04.0 | 2026.04.0 | 2026.04.0 | yes |
| 2026.08.1 | 2026.08.1 | none published | **no** |

On a version with no matching Extended, load via CSV export instead — see
`sql/02_load_csv.sql` and use Cypher's built-in `LOAD CSV`. Everything
downstream (graph model, chain, dashboard) is unchanged.

**`No suitable driver found for jdbc:postgresql://...`**
The JDBC jar is missing from `plugins`, or Neo4j wasn't restarted after it was
added. The file is `postgresql-42.7.x.jar` from
https://jdbc.postgresql.org/download/.

**`Cannot find JDBC url for key pg`**
`apoc.conf` isn't being read. It must sit in `<NEO4J_HOME>\conf` next to
`neo4j.conf`, and the key is exactly `apoc.jdbc.pg.url`. As a one-off test you
can pass the full URL inline instead of the alias:
```cypher
CALL apoc.load.jdbc(
  'jdbc:postgresql://localhost:5432/kgn4j?user=postgres&password=YOURPASS',
  'SELECT count(*) AS n FROM stmt.v_txn_for_graph') YIELD row RETURN row;
```

**`FATAL: password authentication failed`**
If the password contains `& : / ? # @`, URL-encoding inside the connection
string bites. Use the split form in `apoc.conf`:
```properties
apoc.jdbc.pg.url=jdbc:postgresql://localhost:5432/kgn4j
apoc.jdbc.pg.user=postgres
apoc.jdbc.pg.password=your password
```

**`relation "stmt.v_txn_for_graph" does not exist`**
Either `sql/03_view_for_neo4j.sql` wasn't run, or the JDBC URL points at the
wrong database. The database name is the last path segment of the URL.

**Property keys come back NULL in Cypher**
JDBC hands column names through exactly as PostgreSQL folds them — lower case
for unquoted identifiers. Use `row.txn_amt`, never `row.TXN_AMT`.

---

## The chain

**`cypher/04` §4.2 shows `chain_length = 0`**
The account has no rows with `TXN_TYPE_D_C = 'D'` *on its own statement*, or
`TXN_WITH_ACC` is empty on those rows (the view filters those out — a debit
with no counterparty has nowhere to flow to).

**`chain_status = MISMATCH`**
Floating-point drift beyond the 0.005 tolerance, which usually means the
amounts have more than two decimal places. Widen the tolerance in
`cypher/03_build_flow_chain.cypher` (three occurrences of `0.005`).

**Legs are in the wrong order**
See "Ordering" in `docs/DATA_MODEL.md`.

---

## NeoDash

**`npm install` fails on peer dependencies**
Use `npm install --legacy-peer-deps`. Verified working on Node 25.8.1 /
npm 11.11.0: 1932 packages, exit 0, webpack compiled successfully.

**`npm run dev` fails with "yarn is not recognized"**
NeoDash's `dev` script is `yarn webpack-dev-server --mode development`. Without
yarn installed, run the local binary directly:
```bash
npx webpack-dev-server --mode development
```
The first bundle takes ~90 seconds before the page responds.

**"Connection refused" / "WebSocket connection failure"**
NeoDash talks Bolt from the browser. Check port 7687 is listening
(`.\scripts\check-prereqs.ps1`), and try protocol `bolt://` if `neo4j://`
fails — the `neo4j://` scheme does routing discovery that a single Community
instance doesn't need.

**Clicking a table cell does nothing**
The *Report Actions* extension is off (menu → Extensions), or the rule is on
the wrong column. It must be on `STATEMENT_FOR_ACC`. See
`docs/NEODASH_CARDS.md`.

**Clicking a graph node does nothing**
Same extension, and the rule has to exist once per node label — twelve of
them, from `Provider` down to `EndNode` — each reading the `click` property
into the `focus` variable. See `docs/NEODASH_CARDS.md` for the full table.

**The graph renders but nothing moves — nodes won't drag**
The graph card's `layout` was `tree`. NeoDash maps that to react-force-graph's
`dagMode: 'td'` (`src/chart/graph/GraphChartVisualization.ts`), which pins every
node to its depth row: the force simulation cannot move it off that line, so
the whole thing feels frozen. `fixNodeAfterDrag: true` compounded it by nailing
down whatever did get dragged.

The dashboard now ships `layout: "force-directed"` (which leaves `dagMode`
undefined) and `fixNodeAfterDrag: false`. If you want the hierarchy back but
still want to drag, `tree-left-right` is the least constrained of the tree
modes.

The other thing that freezes a graph is the **lock button** in the card's top
right — `lockable` is on, and a locked layout stores fixed positions and
ignores the simulation. Click it again to unlock.

**The graph is empty after rebuilding the tree**
This is the common one. NeoDash keeps `neodash_focus` in **browser
localStorage**, so it survives a rebuild of `:Nav`. Rebuilding renames keys,
and a focus pointing at a key that no longer exists matches nothing — the card
goes blank with no error, which looks exactly like a broken dashboard.

Keys that died in the rename: `users`, `user:<acc>`, `ud:<acc>`,
`creditamt:<acc>`, `debittotal:<acc>`, the old `type:<acc>:<TYPE>` (now
`type:<acc>:<D|C>:<TYPE>`) and `rcpt:…`. Check yours:

```cypher
MATCH (n:Nav {key: 'ud:5631809894'}) RETURN n;
```

No rows means a dead key. All three cards now fall back to `'root'` in that
case, so **reload `dashboards\kgn4j-dashboard.json`** (☰ → Load Dashboard →
Select from file) and the graph comes back on Pathao Pay. Only the drill-down
position is lost.

**The graph is empty and the tree was never built**
Different cause, same symptom. Confirm the navigation layer exists:
```cypher
MATCH (n:Nav) RETURN count(*);
```
Zero means `cypher/03_build_nav_graph.cypher` has not run, or it ran against
an empty `:Transaction` set. Expect ~102,000 on the current data.

**Node captions read `Customer` / `TxnTypeNode` instead of the values**
The card's caption property isn't set. In the graph card's settings, choose
`name` as the displayed property for each label — and `name` for the `EXPANDS`
relationship, which is what puts `138.29 Crore tk` on the edge.
