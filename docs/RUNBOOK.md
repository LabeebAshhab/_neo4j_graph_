# Runbook — step by step

Paths and state on this machine, verified 2026-09-21:

| | |
|---|---|
| Neo4j home | `C:\neo4j\neo4j-community-2026.08.1` |
| Neo4j login | `neo4j` / `1234abcD` |
| PostgreSQL | `C:\Program Files\PostgreSQL\18` |
| psql | `C:\Program Files\PostgreSQL\18\bin\psql.exe` (not on PATH) |
| NeoDash | `C:\Nagad.work\KGN4j\neodash` (installed) |
| Project | `C:\Nagad.work\KGN4j` |

**Already done — do not redo:**
APOC Core and the PostgreSQL JDBC driver are in `plugins\`; `neo4j.conf` is
configured; `conf\apoc.conf` exists; NeoDash's 1932 packages are installed;
Neo4j (7474/7687), PostgreSQL (5432) and the NeoDash dev server (3000) are all
running right now.

**Still to do:** steps 1-6 below. Nothing is in Neo4j yet.

**Your PostgreSQL:** database `neo4j`, table `neo4j`, CSV already imported.

---

## Step 1 - create the two views (pgAdmin)

Your CSV is already imported as table `neo4j` in database `neo4j`, so the
`sql/01`-`03` scripts do not apply - they build a schema from scratch. Use the
adapter instead; it reads your table and changes nothing about it.

1. pgAdmin -> Query Tool **connected to the `neo4j` database**
2. Open and run `C:\Nagad.work\KGN4j\sql\10_adapt_existing_table.sql`

It resolves your column names case-insensitively, so it works whether pgAdmin
created `unq_id` or `"UNQ_ID"`, and whatever the column types are.

It creates:

- `public.v_txn_for_graph` - one clean row per transaction, with `from_acc` /
  `to_acc` derived from `TXN_TYPE_D_C` so money always flows the right way
- `public.v_account_summary` - per-account totals

If the table or schema is not `public.neo4j`, edit `v_schema` / `v_table` in
the DECLARE block of section 2.

**If it raises an error naming missing columns**, run this and send me the
result - it prints exactly how your columns are spelled:

```sql
SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'neo4j';
```

---

## Step 2 - check what the views produced (pgAdmin)

The script ends with three checks. Read them before going on:

- `rows_for_graph` vs `rows_in_source` - a gap is rows dropped because
  `TXN_TYPE_D_C` wasn't D/C, or `TXN_WITH_ACC` was empty. A small gap is
  normal; a large one means a column didn't parse.
- the per-account summary - debit and credit totals per account
- the first 20 graph rows - confirm `from_acc` / `to_acc` point the right way

---

## Step 3 - export the two views (pgAdmin)

`apoc.load.jdbc` does not exist in Neo4j 2026.08.1 (see
`docs/TROUBLESHOOTING.md`), so the handoff is two CSV files in Neo4j's own
`import` folder. Neo4j will not read a CSV from anywhere else.

### Method A - server-side COPY (preferred)

Verified on this machine: the PostgreSQL service runs as
`NT AUTHORITY\NetworkService`, and the import folder grants
`Authenticated Users` Modify, so PostgreSQL can write there itself. This
writes both files with the right names and paths in one shot.

Requires connecting as a superuser (`postgres`) or a role in
`pg_write_server_files`.

```sql
COPY (SELECT * FROM public.v_txn_for_graph ORDER BY statement_for_acc, txn_date_time)
TO 'C:\neo4j\neo4j-community-2026.08.1\import\txn_for_graph.csv'
WITH (FORMAT csv, HEADER true);

COPY (SELECT * FROM public.v_account_summary ORDER BY statement_for_acc)
TO 'C:\neo4j\neo4j-community-2026.08.1\import\account_summary.csv'
WITH (FORMAT csv, HEADER true);
```

Each returns `COPY <n>` - that number is your row count, worth noting for the
comparison in step 4.

If it fails with `permission denied for function copy_to` or `must be
superuser`, your login role lacks the privilege - use Method B.

### Method B - download from the results grid

1. Query Tool on `neo4j`, run:
   ```sql
   SELECT * FROM public.v_txn_for_graph ORDER BY statement_for_acc, txn_date_time;
   ```
2. In the results toolbar click **Download as CSV** (or press F8).
3. pgAdmin saves it to your browser/pgAdmin download location, named something
   like `data-20260921.csv` - it does **not** let you choose the path.
4. Move and rename it:
   ```powershell
   Move-Item "$env:USERPROFILE\Downloads\data-*.csv" 'C:\neo4j\neo4j-community-2026.08.1\import\txn_for_graph.csv' -Force
   ```
5. Repeat for `public.v_account_summary` -> `account_summary.csv`.

Check the *Header* option is on in pgAdmin's export settings either way; the
Cypher reads the files `WITH HEADERS`.

### Confirm both files landed

```powershell
Get-ChildItem 'C:\neo4j\neo4j-community-2026.08.1\import' | Select-Object Name,Length,LastWriteTime
```

Both must be present, and `LastWriteTime` should be just now - the folder
currently holds sample-data files of the same names, and you are overwriting
them.

---

## Step 4 — build the graph (Neo4j Browser)

Open http://localhost:7474, log in as `neo4j` / `1234abcD`.

Run these four files **in order**. Paste the whole file contents into the
query bar — Browser runs multi-statement scripts as long as the semicolons are
intact.

| # | file | what it does |
|---|---|---|
| 1 | `cypher\01_constraints.cypher` | constraints and indexes |
| 2 | `cypher\02b_load_from_csv.cypher` | reads both CSVs → `:Account` / `:Transaction` |
| 3 | `cypher\03_build_nav_graph.cypher` | builds the Pathao Pay drill-down tree |
| 4 | `cypher\04_verify.cypher` | the checks |

Two notes on file 3: it opens with two `:param` lines that Neo4j Browser
supports natively. Leave `pathao_acc` as `null` unless you want to count only
credits from one settlement account, in which case put that account number
there.

File 2 begins with `MATCH (n) DETACH DELETE n` — it wipes the `neo4j` database
before loading. That is intentional and re-runnable, but know it before you
run it on a database holding anything else.

### What step 4 should print

`04_verify.cypher` in order:

- **4.2** one `Provider`, 38 `CustomerPage` nodes, one `Customer` per credited
  customer, and the deeper levels fanning out
- **4.5b** **no rows** — every customer on exactly one page, page ring unbroken
- **4.3** and **4.4** — **no rows** (no orphans, no duplicate paths)
- **4.5** `BALANCED`
- **4.6** and **4.6b** `BALANCED` per customer, debit and credit side
- **4.7** `BALANCED` per transaction type — the counterparty edges plus the
  Others edge must equal the type's amount. `GAP` rows are transactions with
  no `TXN_WITH_ACC` in the source; on the current data there are none.
- **4.7b** a single row: `balanced = TRUE` for every branch
- **4.8** every END node reads `cycles_back_to = root`
- **4.8b** **no rows** — every node from level 3 down carries a table filter

If 4.2 shows no `Nav` rows, the load in step 2 produced no `:Transaction`
nodes — go back and check the CSV export actually has a header row.

---

## Step 5 — NeoDash

The dev server is already running. Open http://localhost:3000.

If it isn't running:

```powershell
cd C:\Nagad.work\KGN4j
.\scripts\setup-neodash.ps1
```

1. **Connect**: protocol `bolt://`, host `localhost`, port `7687`, database
   `neo4j`, user `neo4j`, password `1234abcD`.
2. **Load the dashboard**: menu (top left) → *Load Dashboard* → *Select from
   file* → `C:\Nagad.work\KGN4j\dashboards\kgn4j-dashboard.json` → *Load*.
3. **Enable clicks**: menu → *Extensions* → turn on **Report Actions**.
   Without this nothing is clickable.

---

## Step 6 — walk the drill-down

The graph card opens on **Pathao Pay**. Each click reveals one level:

1. **Pathao Pay** → `Customers 1-10 of 380`, edge = the total credited
2. that → `C1 … C10`. **Click the Customers node again** for `11-20`,
   then `21-30`, wrapping back to the first page at the end
3. a **customer** → `Customer-<account no>`, edge = their total debit + credit
4. that → **TXN_TYPE_D_C**
5. that → **Credit** and **Debit**, edges = credited and debited
6. **Credit** → its transaction types directly ·
   **Debit** → **TXN_TYPE** → its transaction types
7. **P2P / TOP UP / CASH OUT / …**, edge = amount per type
8. a type → `Customer-<account no>` counterparties, edge = amount with each,
   plus an **END** node (and **Others (n customers)** where the tail was
   rolled up)
9. **END** → back to Pathao Pay (the cycle)

Edge captions are short form — `138.29 Crore tk`, not `1382920243.4999224`.
Hover for the exact figure.

The table on the right follows whatever is selected, not just the customer:
**Debit** shows only debits, **CASH OUT** only cash-outs, a bottom-level
`Customer-…` node only the rows between those two accounts. The breadcrumb
across the top shows where you are and prints the filter in force.

---

## Daily restart

```powershell
# window 1 - Neo4j
C:\neo4j\neo4j-community-2026.08.1\bin\neo4j.bat console

# window 2 - NeoDash
cd C:\Nagad.work\KGN4j\neodash ; npx webpack-dev-server --mode development
```

PostgreSQL runs as a Windows service and is already up.

---

## After new data

```
pgAdmin : re-import the CSV into your `neo4j` table
pgAdmin : re-export the two CSVs (step 3) - the views pick up new rows automatically

Neo4j   : run cypher\02b_load_from_csv.cypher, then cypher\03_build_nav_graph.cypher
NeoDash : refresh the browser tab
```

Both Cypher files are idempotent. `03` only rebuilds the `:Nav` tree and never
touches `:Transaction` or `:Account`, so you can re-run it alone after changing
`pathao_acc`.
