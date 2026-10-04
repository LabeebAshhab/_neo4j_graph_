# Money Trail — where does a credited amount terminate?

A second page, **Money Trail**, in `dashboards/kgn4j-dashboard-trail.json`.
The original `dashboards/kgn4j-dashboard.json` is unchanged — load it to get
the previous dashboard back exactly as it was.

## The question it answers

> Customer 1 got 500 tk credited. After that, which debits used it up, and on
> which debit — at what date and time — did the last of it (down to
> 0.0001 tk) leave the account?

## How to use it

1. **Pick a customer** — click a `C1`, `C2`, … button.
2. **Pick a credit to trace** — every credit into that account, oldest first.
   Click `TRACE`. Use the column filter in the table header to find a date or
   amount.
3. Read the answer:
   * **Where did it terminate?** — terminated at (date-time), the terminating
     debit, how many debits used the credit, how long it took.
   * **Money trail** (graph) — sender → credit → each debit in time order →
     `TERMINATED` node. Long trails show the first 6 and last 6 steps with the
     middle folded into one "… n more debits" node.
   * **Money trail – every step** (table) — every debit, the part of it paid
     from this credit (`FROM_THIS_CREDIT`), and what was left of the credit
     after it (`CREDIT_LEFT_AFTER`). The terminating row says
     `TERMINATED HERE`.
4. **Trace rule** — switch between:
   * `credit_first` (default): every debit after the credit is paid from this
     credit first.
   * `fifo`: money already in the account before the credit is spent first;
     this credit is used only after that older balance is gone.

All debit types count: P2P, TOP UP, CASH OUT, PAYMENT, BILL PAYMENT, service
fees and the rest — everything that left the account.

## Exactness

Amounts are added up as integer micro-taka (× 1,000,000), not floating point,
so the trail does not stop while even 0.000001 tk of the credit is left, and
it stops on exactly the debit that uses the last of it.

## Duplicated rows in the source

For 7 accounts — including C1–C5 — every real statement line is present in
`public.neo4j` **414 times** (828 for some lines of C3), each copy with a
different `TXN_ID` but the same time, serial, amount, counterparty and
balance-after. For example, C1 has 1,228,752 rows but 2,968 real lines.
About 5.9M of the 6.7M rows are these copies.

The trail reads one representative of each real line (label `:Canon`, built by
`cypher/05_build_trace_layer.cypher`), so a credit is not "spent" 414 times
by the same debit. **The Pathao Pay drill-down page still reads every raw
row**, so its totals for those accounts are inflated about 414×. That page was
deliberately left as it was. The duplication should be fixed at the source
(the query that built `public.neo4j`).

## Setting it up

1. `cypher/05_build_trace_layer.cypher` — run once after every data reload
   (about a minute). It only adds the `:Canon` label, a `dup_count` property
   and two indexes. Nothing existing is changed.
2. NeoDash patch — `neodash-patches/kgn4j-neodash.patch`, applied
   automatically by `scripts/setup-neodash.ps1`. It adds two opt-in card
   settings (dashboards that don't use them behave exactly like stock NeoDash):
   * graph `pinAllAfterLayout` — lay the graph out again and fit it to the
     window on every click, then pin every node so **dragging a node moves
     only that node**.
   * table `defaultPageSize` — rows per page when a table loads.
3. Load `dashboards/kgn4j-dashboard-trail.json` in NeoDash (☰ → Load / Import)
   and make sure **Extensions → Report Actions** is on.

The card queries live in `cypher/trace/*.cypher`. After editing one, run
`python scripts/build_trail_dashboard.py` to regenerate the dashboard JSON.

## Going back

* **Dashboard:** load `dashboards/kgn4j-dashboard.json` (untouched).
* **Database:** run `cypher/05_undo_trace_layer.cypher`.
* **Code:** the git tag `before-money-trail` marks the project as it was.
* **NeoDash:** in `neodash\`, run `git apply --reverse ..\neodash-patches\kgn4j-neodash.patch`
  (not needed for the old dashboard, which doesn't use the new settings).

## Limits

* The trail follows money **within the credited customer's own account**. In
  this extract none of the 380 statement customers ever pays another statement
  customer, so a payment can't be followed into the recipient's account. Their
  statements aren't in the data.
* A trail reads at most 20,000 debits after the credit. If the credit still
  isn't used up by then, it says so.
* The credits list shows the first 5,000 credits of an account.
