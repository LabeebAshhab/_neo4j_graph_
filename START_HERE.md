# START HERE

Everything, in order. Ignore every other document until this one is done.

> **Setting this up on a different laptop?** Use
> [`docs/NEW_MACHINE.md`](docs/NEW_MACHINE.md) instead — it covers the parts
> that do not travel with a clone (the data, the Neo4j config, the commit that
> does not exist yet).

---

## What this project is

Your transaction table in PostgreSQL → Neo4j → a NeoDash dashboard with a
table and a click-through graph side by side.

```
PostgreSQL (your table: database `neo4j`, table `public.neo4j`, 6.7M rows)
        |
        |  one view + one CSV export
        v
Neo4j Community 2026.08.1  (localhost:7474 / 7687)
        |
        |  three Cypher scripts
        v
NeoDash (localhost:3000)  -  table card + drill-down graph card
```

---

## What is already done (don't redo any of this)

| | |
|---|---|
| Neo4j | installed, running, memory tuned for a large load |
| Neo4j login | `neo4j` / `1234abcD` |
| APOC + PostgreSQL JDBC driver | installed in `plugins\` |
| NeoDash | installed and running at http://localhost:3000 |
| All Cypher scripts | written and tested end-to-end |
| The dashboard | built: `dashboards\kgn4j-dashboard.json` |
| PostgreSQL | running; your 6.7M rows are already imported |

Neo4j currently holds **17 rows of sample data** that I used to prove the
pipeline works. Your real data replaces it in step 3.

---

## What is left: 5 steps

Steps 1 and 2 are in pgAdmin and are yours, because pgAdmin holds your
database password and I don't handle those. Step 3 is mine. Steps 4 and 5
are a few clicks.

---

### STEP 1 — create the view (pgAdmin, ~1 minute)

1. Open pgAdmin.
2. Query Tool, **connected to the `neo4j` database** (check the tab header -
   this is the single easiest thing to get wrong).
3. Open `C:\Nagad.work\KGN4j\sql\01_view.sql` and run it (F5).

It creates two views and changes nothing about your table. It ends with a
check that prints two numbers:

```
base_table_rows   view_rows
6746792           6746792
```

**Both numbers must be about 6.7 million.** If `view_rows` is 0, stop and
tell me - don't continue, everything downstream would be empty.

> This is the third SQL file I have given you, and the only one that matters
> now. The earlier two are in `sql\legacy\`: one built its query with dynamic
> SQL and silently produced an empty view, the other parsed dates with a
> function that is fine on small tables and unusably slow on 6.7M rows. This
> one has no functions and no date parsing at all.

---

### STEP 2 — export two CSV files (pgAdmin, ~2-5 minutes)

Run these two commands. **Do not add `ORDER BY`** - sorting 6.7M rows costs
minutes and nothing downstream needs it.

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

Each prints a row count. You want roughly:

```
COPY 6746792
COPY 50
```

**If the first prints `COPY 0`, stop and tell me.** That happened before and
means the view is empty.

The first file will be around 1 GB. Both overwrite sample files of the same
names that are sitting there now - that is intended.

Why `COPY` and not the download button: at 6.7M rows the results-grid export
is not viable. `COPY` writes server-side, straight to the right path.
PostgreSQL runs as `NT AUTHORITY\NetworkService` and that folder allows it -
already checked.

---

### STEP 3 — load Neo4j (mine)

Tell me the two `COPY` numbers and I run:

| file | what it does |
|---|---|
| `cypher\01_constraints.cypher` | constraints and indexes (already applied) |
| `cypher\02b_load_from_csv.cypher` | reads both CSVs into `:Account` / `:Transaction` |
| `cypher\03_build_nav_graph.cypher` | builds the Pathao Pay drill-down tree |
| `cypher\04_verify.cypher` | checks every total balances |

Expect 10-30 minutes for the load. I'll report the real node counts and the
balance checks.

If you'd rather run it yourself: http://localhost:7474, log in as
`neo4j` / `1234abcD`, paste each file's contents in that order.

---

### STEP 4 — open the dashboard (yours, ~1 minute)

1. Go to http://localhost:3000 (already running).
2. Click **New Dashboard**.
3. Connection dialog:

   | field | value |
   |---|---|
   | Protocol | `bolt://` |
   | Hostname | `localhost` |
   | Port | `7687` |
   | Database | `neo4j` |
   | Username | `neo4j` |
   | Password | `1234abcD` |

4. **Connect**.
5. Menu **☰** (top left) → **Load Dashboard** → **Select from file** →
   `C:\Nagad.work\KGN4j\dashboards\kgn4j-dashboard.json` → **Load**.
6. Menu **☰** → **Extensions** → turn on **Report Actions**.
   **Do not skip this** - without it the graph draws but nothing is
   clickable, which looks like the dashboard is broken.

---

### STEP 5 — use it

The page has three cards: a breadcrumb across the top, the graph bottom-left,
your transactions table bottom-right.

The graph starts on **Pathao Pay**. Each click opens one more level:

```
Pathao Pay
  -> Customers 1-10 of 380                edge = total credited
      |   click it again for 11-20, 21-30, ... wrapping at the end
      -> C1 / C2 / C3 ... C10             edge = that customer's credit
          -> Customer-<account no>        edge = their total debit + credit
              -> TXN_TYPE_D_C             edge = the same total
                  -> Credit               edge = credited
                  |    -> P2P / TOP UP / CASH OUT / ...   edge = amount
                  |        -> Customer-<account no>       edge = amount
                  |        -> END
                  -> Debit                edge = debited
                       -> TXN_TYPE        edge = debited
                           -> P2P / TOP UP / CASH OUT / ...  edge = amount
                               -> Customer-<account no>      edge = amount
                               -> END     click it to return to Pathao Pay
```

Every amount on an edge is short form: `138.29 Crore tk`, not
`1382920243.4999224`. Hover the edge for the exact figure.

The last level stops expanding once the counterparty amounts add up to the
transaction type's total — the point where that branch balances — and then
draws an **END** node. Where that would take more than 100 nodes, the tail
is collapsed into one **Others (n customers)** node holding the remainder,
so the branch still balances exactly.

The table follows whatever you click, not just the customer: pick **Debit**
and it shows only their debits, **CASH OUT** and only their cash-outs,
a **Customer-…** node at the bottom and only the rows between those two
accounts. The breadcrumb card spells out the filter in force.

---

## If something goes wrong

| symptom | cause |
|---|---|
| `view_rows` is 0 in step 1 | tell me, don't continue |
| `COPY 0` in step 2 | same |
| Graph is empty in NeoDash | the load ran against empty CSVs |
| Graph draws but clicks do nothing | Report Actions extension is off (step 4.6) |
| NeoDash won't connect | try `neo4j://` instead of `bolt://` |

`docs\TROUBLESHOOTING.md` has the longer list.

---

## Settings you may want to change later

In `cypher\03_build_nav_graph.cypher`:

```cypher
:param pathao_acc        => null;   // null = every credit counts as from Pathao Pay
:param top_customers     => 500;    // guard; you have 380 customers so nothing is cut
:param max_counterparties => 100;   // nodes drawn per type before "Others" absorbs the rest
```

`max_counterparties` is the one that matters at your scale. One transaction
type in this data has 2,259 distinct counterparties, and a node per
counterparty is neither readable nor useful. Raising it shows a longer tail;
it changes no total, because the Others node always carries whatever is left.

**One thing I still need from you:** `pathao_acc` is `null`, meaning every
credit on a customer statement is treated as coming from Pathao Pay. If only
credits from one specific settlement account should count, give me that
account number.
