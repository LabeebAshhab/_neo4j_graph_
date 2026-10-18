# Layered Trail — fourth pipeline

PostgreSQL table `public.layered` (database `neo4j`) → Neo4j → NeoDash
dashboard `dashboards/kgn4j-dashboard-layered.json`. It is **P2P only**, and
the graph opens **one person at a time**.

**Nothing else changes.** The Pathao Pay drill-down, the Money Trail and the
Suspect Network run exactly as before. In Neo4j this pipeline only creates and
deletes `:LyrTxn` (the rows) and `:LNet` / `:LFLOW` / `:LLegend` (the graph).
PostgreSQL is only read.

## How to run it

Neo4j must be running first. Start it **once**, in one window:

```powershell
& "$env:NEO4J_HOME\bin\neo4j.bat" console
```

Leave that window open. If you see `Lock file has been locked by another
process`, Neo4j is **already running** somewhere else (another window, or
Neo4j Desktop). Use that one, or close it first. Two copies cannot open the
same database.

Then:

| step | where | what |
|---|---|---|
| 1 | PowerShell, in `C:\Nagad.work\KGN4j` | `python scripts\load_layered_from_pg.py` |
| 2 | NeoDash, http://localhost:3000 | Load Dashboard → `dashboards\kgn4j-dashboard-layered.json` |
| 3 | NeoDash menu → Extensions | turn on **Report Actions** (needed for the clicks) |

Step 1 asks for the PostgreSQL password and the Neo4j password. It reads the
table, loads it into Neo4j, builds the graph, and prints the check (every trail
`OK`). Run it again whenever the table changes; it replaces only its own data.

The script's defaults are host `localhost:5432`, database `neo4j`, user
`postgres`, table `public.layered`, and Neo4j at `http://localhost:7474`. To
use something else, set `PGDATABASE`, `PGTABLE`, `PGHOST`, `PGUSER` or
`NEO4J_HTTP` before running it.

### Why a script and not a direct pgAdmin → Neo4j connection

Neo4j can read PostgreSQL itself with `apoc.load.jdbc`, but on Neo4j 2026.08.1
that procedure is only in **APOC Extended**. No Extended release exists for
2026.08; the latest is 2026.04.0, and that one stops 2026.08.1 from starting
(see `docs/TROUBLESHOOTING.md`). The script does the same job from outside.
It reads the table with `psycopg` and writes to Neo4j over its HTTP API. No CSV
file is involved.

## The rule

Only **P2P** rows count. Cash Out, Top Up and Transfer Money (card) rows are
left out of the trace and the graph.

* A **layer-1** P2P transfer is traced in full. It is the money being followed.
* A **layer-L** P2P transfer out of person X (L ≥ 2) can only carry money X
  **received by P2P in layer L-1** of the same `TXN_SL_TAG`. X's transfers are
  taken **earliest first (FIFO)** against that money:
  ```
  balance += every traced layer-(L-1) P2P amount X received
  each layer-L P2P transfer takes min(amount, balance)
  ```
* What a transfer sends beyond that is the **minus**. It is drawn **orange** and
  not counted. X received 50 and sent 100 → 50 traced, 50 minus.
* A transfer can only use money that had **already arrived**, by
  `APPROVAL_DATETIME`.
* Nobody passes on more than they received, so the traced money kept by
  everyone adds up to the layer-1 amount. The **Does it add up?** card shows
  this.

Your example:

```
ac-1 --500--> ac5            layer 1   traced 500
ac5  --200--> ac3            layer 2   traced 200     (ac5 keeps 100)
ac5  --200--> ac2            layer 2   traced 200
ac2  --50---> ac6            layer 3   traced 50      (ac2 keeps 150)
ac6  --100--> ac7            layer 4   traced 50, minus 50 (orange)
kept: ac5 100 + ac3 200 + ac2 150 + ac7 50 = 500  = ac-1's 500
```

### The current table, checked

| TXN_SL_TAG | layer-1 P2P | kept by people | non-P2P rows left out |
|---|---:|---:|---:|
| 2 | 35,000 | 35,000 ✓ | 0 |
| 3 | 49,995 | 49,995 ✓ | 1 (the 49,000 card transfer) |
| 4 | 49,995 | 49,995 ✓ | 13 |

Trail 4 has 5 P2P transfers with a minus. `01751161891` received 25,460 and
paid 15,000, then 15,000. The second carries 10,460, with **-4,540**.
`01318971555` received 6,080 and paid 6,075, then 8,000. Only 5 of the 8,000
counts, so the people after it carry 5 tk of the traced money.

`python scripts\check_layered_trace.py` recomputes this in plain Python from
the same table (no Neo4j) and lists every row with a minus.

## The graph

```
start:          (SRC) --49,995--> (49,995) 01912673646  pays 5 people
click it:                          (49,995) --25,460--> (25,460) 01751161891  pays 2 people
                                            --9,336---> (9,336)  01767317994  pays 1 person
                                            --5,080---> [5,080]  01725429852  kept 5,080
                                            ...
click 01318971555:                                     (6,080) --6,075--------> (6,075) 01780536672
                                                               --5  (-7,995)--> (5)     01337177039   orange
```

* **Start:** every source, and the person it paid in layer 1.
* **Click a person:** the people they paid by P2P appear in the next column,
  fanned out beside them.
* **Click one of those:** the path you came along stays open, and the next
  level opens.
* **Click any LAYER header:** everything closes again.

| Shape | Colour | Means |
|---|---|---|
| hexagon | wine | source: who sent the layer-1 money |
| circle | by layer: blue, green, purple, pink, slate | a person who paid others on; click to open them |
| square | same layer colours | a person who paid nobody on by P2P; the trail ends there |
| box | pale grey | column header (SOURCE, LAYER 1 …) |
| arrow | grey | fully traced; the caption is the traced amount |
| arrow | **orange** | part of it is minus; the caption is `traced  (-minus)` |

Inside a node is the traced amount the person received. Beside it are the
account number and a second line: `pays N people`, `kept X`,
`-Y not traced`. Several transfers between the same two people are one arrow,
with `xN` on the caption. The legend card (top left) shows all of this.

A node is **one account at one layer** of one trail. An account that turns up
in two layers is drawn twice; the **Selected** card's `ALSO_IN_LAYERS` lists
the other layers.

### The cards

* **What the shapes and colours mean**: the legend.
* **Layered money trail**: the graph.
* **Selected**: the clicked person: traced in, received, how many people they
  paid, sent, traced out, minus, kept.
* **Does it add up?**: per trail, the layer-1 amount and what everyone kept
  (`CHECK = OK`), plus the non-P2P rows left out.
* **By layer**: per layer, people, sent, traced, minus, kept, and passed on.
* **P2P transactions on the arrows shown**: the rows behind what is drawn,
  with `TRACED_AMT` and `MINUS_AMT`. It has a CSV download.

## Files

| file | what |
|---|---|
| `scripts/load_layered_from_pg.py` | PostgreSQL → Neo4j, then builds the graph (**the one you run**) |
| `cypher/layered/01_build_layered_graph.cypher` | the trace and the graph; the script runs it, or paste it into Neo4j Browser to rebuild from rows already loaded |
| `cypher/layered/cards/*.cypher` | the query behind each dashboard card |
| `dashboards/kgn4j-dashboard-layered.json` | the dashboard; regenerate with `python scripts\build_layered_dashboard.py` after editing a card |
| `scripts/check_layered_trace.py` | the same rule in plain Python, for checking |
| `cypher/layered/99_undo_layered.cypher` | removes everything this pipeline created |

Settings at the top of `01_build_layered_graph.cypher`:

```
:param respect_time => true;   // a transfer can only carry money that had already arrived
:param col_gap      => 300.0;  // space between layer columns
:param row_gap      => 46.0;   // space between people in one fan
:param tree_gap     => 90.0;   // extra space between trails
```

The shapes, outside labels and pinned positions come from
`neodash-patches/kgn4j-suspect-graph.patch`, which is already applied. No new
patch is needed.
