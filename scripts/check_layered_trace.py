"""
KGN4j - Layered Trail : independent check of the capped-flow rule

Usage (from the project root):
    python scripts/check_layered_trace.py

Reads the `layered` table from PostgreSQL (same connection settings and
password prompt as scripts/load_layered_from_pg.py) and recomputes, in
plain Python and without Neo4j, what cypher/layered/01_build_layered_graph.cypher
computes, so the two can be compared. Nothing is written anywhere.

THE RULE (P2P only - other TXN_TYPEs are left out)
  A layer-1 P2P transfer is traced in full - it is the money followed.
  A layer-L P2P transfer out of account X (L >= 2) can only carry money X
  received by P2P in layer L-1 (same TXN_SL_TAG). X's transfers are walked
  in time order (FIFO) against that money:
      balance += every traced layer-(L-1) P2P amount X received
      each layer-L P2P transfer takes min(amount, balance)
  X received 50 and sent 100 -> 50 is traced, 50 is minus.
"""
import getpass
import os
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from load_layered_from_pg import PG, PG_TABLE, read_postgres  # noqa: E402


def main():
    pw = os.environ.get('PGPASSWORD') or getpass.getpass(
        f'PostgreSQL password for {PG["user"]}@{PG["host"]}/{PG["dbname"]}: ')
    rows = [r for r in read_postgres(pw) if r['txn_type'].upper() == 'P2P']
    for r in rows:
        r['t'] = datetime.fromisoformat(r['ts'])
        r['traced'] = r['amount'] if r['layer'] == 1 else 0.0

    for layer in range(2, max(r['layer'] for r in rows) + 1):
        groups = defaultdict(list)
        for r in rows:
            if r['layer'] == layer:
                groups[(r['tag'], r['from_acc'])].append(r)
        for (tag, acc), outs in groups.items():
            ins = [r for r in rows if r['tag'] == tag and r['layer'] == layer - 1 and r['with_acc'] == acc]
            # inflows sort before outflows on the same timestamp
            events = sorted([(r['t'], 0, r['txn_id'], r) for r in ins] +
                            [(r['t'], 1, r['txn_id'], r) for r in outs], key=lambda e: e[:3])
            bal = 0.0
            for _, is_out, _, r in events:
                if not is_out:
                    bal += r['traced']
                else:
                    r['traced'] = min(r['amount'], bal)
                    bal -= r['traced']

    print(f'{len(rows)} P2P rows from {PG["dbname"]}.{PG_TABLE}\n')
    for tag in sorted({r['tag'] for r in rows}, key=lambda t: (len(t), t)):
        tr = [r for r in rows if r['tag'] == tag]
        start = sum(r['amount'] for r in tr if r['layer'] == 1)
        print(f'=== TXN_SL_TAG {tag}   layer-1 amount {start:,.2f}')
        print(f"{'layer':>5} {'txns':>5} {'sent':>12} {'traced':>12} {'minus':>12}")
        for L in sorted({r['layer'] for r in tr}):
            lr = [r for r in tr if r['layer'] == L]
            s, t = sum(r['amount'] for r in lr), sum(r['traced'] for r in lr)
            print(f'{L:>5} {len(lr):>5} {s:>12,.2f} {t:>12,.2f} {s - t:>12,.2f}')
        # kept = traced in - traced out, per (layer, account)
        kept = defaultdict(float)
        for r in tr:
            kept[(r['layer'], r['with_acc'])] += r['traced']
            if r['layer'] > 1:
                kept[(r['layer'] - 1, r['from_acc'])] -= r['traced']
        total = sum(kept.values())
        ok = 'OK' if abs(total - start) < 0.005 else 'MISMATCH'
        print(f'kept by people {total:,.2f} vs layer-1 {start:,.2f}  {ok}\n')

    print('rows with a minus (traced < amount):')
    for r in sorted(rows, key=lambda r: (r['tag'], r['layer'], r['t'])):
        if r['traced'] < r['amount'] - 1e-9:
            print(f"  tag {r['tag']} L{r['layer']} {r['txn_id']} {r['from_acc']} -> {r['with_acc']}"
                  f"  sent {r['amount']:,.2f}  traced {r['traced']:,.2f}  minus {r['amount'] - r['traced']:,.2f}")


if __name__ == '__main__':
    main()
