# Running KGN4j on another laptop

Assumes pgAdmin, PostgreSQL, Neo4j, Node.js and NeoDash are already installed
there. Six steps, roughly 30-60 minutes, most of it the CSV load.

Work top to bottom. Every step ends with a number to check — if a number is
wrong, stop there, because everything after it will be empty.

**Shell:** every command here is **PowerShell**. Where a command starts with a
quoted path, the leading `&` is required — it is PowerShell's call operator.
Without it PowerShell parses the quoted path as a string and fails with
`Unexpected token '-a' in expression or statement.`

---

## Before you clone: two things that do NOT travel

### 1. The repo has no commits yet

There is nothing to clone until this one is run **on this laptop**:

```bash
cd C:\Nagad.work\KGN4j && git add -A && git commit -m "KGN4j pipeline"
```

Push it somewhere, or copy the folder to the other laptop directly.

First delete the eight 0-byte junk files in the project root — `'credit`,
`'dc`, `'debit`, `'debittotal`, `'root'`, `'ud`, `'user`, `'users'`. They are
accidental artifacts of a shell that mis-parsed a `:param` line, all empty,
and there is no reason to carry them:

```bash
cd C:\Nagad.work\KGN4j && rm -f "'credit" "'dc" "'debit" "'debittotal" "'root'" "'ud" "'user" "'users'"
```

### 2. The data is not in the repo

`.gitignore` excludes `data/*.csv`, and the source is ~1 GB regardless. Only
`data/sample_transactions.csv` (17 rows, same 17 columns) is committed, which
is enough to prove the pipeline end to end but is not your real data.

Move the real rows yourself — see step 1.

---

## What you do NOT need

Worth saying up front, because the older docs in this repo imply otherwise:

| Not needed | Why |
|---|---|
| APOC | The pipeline uses `LOAD CSV` and `CALL { } IN TRANSACTIONS`, both core Cypher. APOC appears in `02b` only in a comment. |
| PostgreSQL JDBC driver | Only `cypher/02_load_from_postgres.cypher` used it, and that file is superseded by the CSV path. |
| `config/apoc.conf` | Same reason. |

If Neo4j starts and `LOAD CSV` works, you have everything.

---

## Step 0 — fill in your three values

These are the only machine-specific things. Write them down; every command
below refers to them.

| | this laptop | yours |
|---|---|---|
| `NEO4J_HOME` | `C:\neo4j\neo4j-community-2026.08.1` | ? |
| Neo4j password | `1234abcD` | ? |
| PostgreSQL database / table | db `neo4j`, table `public.neo4j` | ? |

Find `NEO4J_HOME` if unsure — it is the folder containing `bin\neo4j.bat`.

If your PostgreSQL table is not `public.neo4j`, edit the three references in
`sql/01_view.sql` (lines 84, 105 and the header comment) before running it.

---

## Step 1 — get the transactions into PostgreSQL

Pick one. Both end with the rows in a table the views can read.

### Option A — you still have the source CSV (simplest)

In pgAdmin on the new laptop:

1. Create a database named `neo4j`.
2. Create the table. The 17 columns, in file order, are:
   `UNQ_ID, FROM_DATE, TO_DATE, SerialNo, TXN_DATE_TIME, TXN_ID, TXN_TYPE,
   ACCOUNT_TYPE, STATEMENT_FOR_ACC, TXN_WITH_ACC, CHANNEL, REFERENCE,
   TXN_TYPE_D_C, STATUS, TXN_AMT, AVAILABLE_BLC_AFTER_TXN, TXN_WITH_INFO`.
   `text` for all of them is fine — `sql/01_view.sql` casts what it needs and
   never parses dates.
3. Right-click the table → **Import/Export Data** → Import, *Header* **Yes**,
   *Delimiter* `,`, *Encoding* `UTF8`.

### Option B — copy the table straight across (faster, exact)

On **this** laptop:

```bash
"C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -d neo4j -t public.neo4j -Fc -f kgn4j_table.dump
```

Copy `kgn4j_table.dump` over, then on the **new** laptop:

```bash
"C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -U postgres -d neo4j -t neo4j kgn4j_table.dump
```

Create the empty `neo4j` database first. Both prompt for the PostgreSQL
password — type it yourself, it is not stored in the repo.

**Check before moving on**, in pgAdmin:

```sql
SELECT count(*) FROM public.neo4j;
```

Expect your full row count (~6.7 M here). If it is 0, stop.

---

## Step 2 — configure Neo4j

Open `<NEO4J_HOME>\conf\neo4j.conf` and make sure these are present and
uncommented. The memory lines are what make a multi-million-row load finish
instead of thrashing:

```properties
server.directories.import=import
server.bolt.enabled=true
server.http.enabled=true

server.memory.heap.initial_size=4g
server.memory.heap.max_size=4g
server.memory.pagecache.size=6g
```

Those values assume **16 GB RAM**. On 8 GB use `2g` heap and `2g` pagecache.
Heap + pagecache should leave at least 4 GB for the OS.

Then start Neo4j and set the password:

```bash
& "<NEO4J_HOME>\bin\neo4j.bat" console
```

Leave that window open. On first start Neo4j forces a password change from the
default `neo4j`/`neo4j` at http://localhost:7474 — set it to whatever you
recorded in step 0.

**Check:** http://localhost:7474 loads and you can log in.

---

## Step 3 — create the two views

pgAdmin → Query Tool, **connected to the `neo4j` database** (check the tab
header; this is the easiest thing to get wrong). Open and run:

```
sql\01_view.sql
```

It creates `v_txn_for_graph` and `v_account_summary` and changes nothing about
your table. It ends by printing two numbers:

```
base_table_rows   view_rows
6746792           6746792
```

**Both must be roughly your row count. If `view_rows` is 0, stop** — every
later step would produce an empty graph.

---

## Step 4 — export both views into Neo4j's import folder

Neo4j reads CSVs only from its own `import` directory. Run both in pgAdmin,
substituting your `NEO4J_HOME`. **Do not add `ORDER BY`** — sorting millions
of rows costs minutes and nothing downstream needs it.

```sql
COPY (SELECT * FROM public.v_txn_for_graph)
TO 'C:\neo4j\neo4j-community-2026.08.1\import\txn_for_graph.csv'
WITH (FORMAT csv, HEADER true);
```

```sql
COPY (SELECT * FROM public.v_account_summary)
TO 'C:\neo4j\neo4j-community-2026.08.1\import\account_summary.csv'
WITH (FORMAT csv, HEADER true);
```

Each prints `COPY <n>`. Expect ~6.7 M and ~380. **If the first prints
`COPY 0`, stop.**

`COPY` writes server-side, so the PostgreSQL service account needs write
permission on that folder. If it fails with *permission denied*, either grant
`Authenticated Users` Modify on `<NEO4J_HOME>\import`, or run the query
without `TO`, use pgAdmin's **Download as CSV** (F8), and move the file:

```bash
mv ~/Downloads/data-*.csv "/c/neo4j/neo4j-community-2026.08.1/import/txn_for_graph.csv"
```

If it fails with *must be superuser*, connect as `postgres`.

---

## Step 5 — build the graph

Four files, **in this order**. From the project folder, one command each:

```bash
& "<NEO4J_HOME>\bin\cypher-shell.bat" -a bolt://localhost:7687 -u neo4j -p YOUR_PASSWORD -d neo4j --file cypher/01_constraints.cypher
```

```bash
& "<NEO4J_HOME>\bin\cypher-shell.bat" -a bolt://localhost:7687 -u neo4j -p YOUR_PASSWORD -d neo4j --file cypher/02b_load_from_csv.cypher
```

```bash
& "<NEO4J_HOME>\bin\cypher-shell.bat" -a bolt://localhost:7687 -u neo4j -p YOUR_PASSWORD -d neo4j --file cypher/03_build_nav_graph.cypher
```

```bash
& "<NEO4J_HOME>\bin\cypher-shell.bat" -a bolt://localhost:7687 -u neo4j -p YOUR_PASSWORD -d neo4j --file cypher/04_verify.cypher
```

| file | does | takes |
|---|---|---|
| `01_constraints` | constraints + indexes. **Must run first** or every `MERGE` in `02b` degrades to a full scan | seconds |
| `02b_load_from_csv` | both CSVs → `:Account` / `:Transaction` | 10-30 min |
| `03_build_nav_graph` | the Pathao Pay drill-down tree | ~2 min |
| `04_verify` | the checks | ~1 min |

`02b` starts with `MATCH (n) DETACH DELETE n` — it wipes the `neo4j` database
first. Intended and re-runnable, but know it before pointing this at a
database holding anything else.

Prefer a GUI? http://localhost:7474, log in, paste each file's whole contents
into the query bar in the same order. Browser runs multi-statement scripts and
supports the `:param` lines at the top of `03`.

**Check** — `03` ends by printing node counts per level. On this laptop's data:

```
1  Provider            1
2  CustomerPage       38
3  Customer          380
...
10 CounterpartyNode 89546
```

`04_verify` should print `BALANCED` throughout and no rows for the orphan,
duplicate-path and paging checks. `docs/RUNBOOK.md` lists what each check
means.

---

## Step 6 — NeoDash

```bash
cd <project folder> && powershell -ExecutionPolicy Bypass -File scripts\setup-neodash.ps1
```

Clones NeoDash into `.\neodash` if missing (it is git-ignored, so a fresh
clone will not have it), runs `npm install --legacy-peer-deps`, and starts the
dev server on http://localhost:3000. First compile takes 60-90 seconds —
until it finishes the port accepts connections but returns nothing, which
looks like a hang and is not one.

Then in the browser:

1. **Connect** — protocol `bolt://`, host `localhost`, port `7687`, database
   `neo4j`, user `neo4j`, and your password.
2. **☰ → Load Dashboard → Select from file** →
   `dashboards\kgn4j-dashboard.json` → **Load**.
3. **☰ → Extensions → Report Actions** — turn it **on**. Without it the graph
   draws but no click does anything, which looks like a broken dashboard.

---

## Running it again later

Nothing here is a Windows service. Both stop when their window closes or the
machine reboots, and both must be running for the dashboard to work.

```bash
& "<NEO4J_HOME>\bin\neo4j.bat" console
```

```bash
cd <project folder> && powershell -ExecutionPolicy Bypass -File scripts\setup-neodash.ps1
```

One window each, left open. The graph itself survives — it is on disk in
Neo4j, so you only re-run step 5 when the source data changes.

---

## If something goes wrong

| symptom | cause |
|---|---|
| `view_rows` is 0 in step 3 | the table name in `sql/01_view.sql` does not match yours |
| `COPY 0` in step 4 | same |
| `Couldn't load the external resource` in step 5 | the CSVs are not in `<NEO4J_HOME>\import`, or `server.directories.import` was changed |
| `02b` runs out of heap | memory settings in step 2 not applied, or Neo4j not restarted after editing the conf |
| graph card empty | the tree was not built (step 5 file 3), or a stale `neodash_focus` — reload the dashboard JSON |
| clicks do nothing | Report Actions extension off (step 6.3) |
| graph will not drag | the card's lock button is on, top-right of the graph card |
| NeoDash will not connect | try `neo4j://` instead of `bolt://` |

`docs/TROUBLESHOOTING.md` has the longer list.
