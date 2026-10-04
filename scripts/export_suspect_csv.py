"""
KGN4j - Suspect Network, step 1 : spreadsheet -> CSV in Neo4j's import folder

Usage (from the project root):
    python scripts/export_suspect_csv.py [path\\to\\Book1.xlsx] [import_dir]

Defaults:
    xlsx        %USERPROFILE%\\Downloads\\Book1.xlsx
    import_dir  C:\\neo4j\\neo4j-community-2026.08.1\\import

Writes <import_dir>\\suspect_wallet_txn.csv with the six source columns:
    SUSPECTED_WALLET, TXN_WITH_ACC, TXN_TYPE, TXN_MODE, TXN_COUNT, TXN_AMOUNT

Account numbers are written as text so the leading 0 survives
(01767091999 must not become 1767091999).

This is a separate pipeline from the Pathao Pay drill-down: it does not
read or write PostgreSQL, txn_for_graph.csv or anything cypher/02b-05 use.
Needs: pip install openpyxl
"""
import csv
import os
import sys
from pathlib import Path

import openpyxl

COLUMNS = ['SUSPECTED_WALLET', 'TXN_WITH_ACC', 'TXN_TYPE', 'TXN_MODE', 'TXN_COUNT', 'TXN_AMOUNT']

src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(os.environ['USERPROFILE']) / 'Downloads' / 'Book1.xlsx'
imp = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r'C:\neo4j\neo4j-community-2026.08.1\import')
out = imp / 'suspect_wallet_txn.csv'


def acc(v):
    # Excel may hand back an int if the column was not stored as text
    if v is None:
        return ''
    s = str(v).strip()
    if s.endswith('.0'):
        s = s[:-2]
    if s.isdigit() and len(s) == 10:
        s = '0' + s
    return s


wb = openpyxl.load_workbook(src, read_only=True, data_only=True)
ws = wb.active
rows = ws.iter_rows(values_only=True)
header = [str(h).strip().upper() if h is not None else '' for h in next(rows)]
missing = [c for c in COLUMNS if c not in header]
if missing:
    sys.exit(f'{src}: missing column(s) {missing}; found {header}')
ix = {c: header.index(c) for c in COLUMNS}

n = skipped = 0
total = 0.0
with out.open('w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(COLUMNS)
    for r in rows:
        wallet, with_acc = acc(r[ix['SUSPECTED_WALLET']]), acc(r[ix['TXN_WITH_ACC']])
        if not wallet:
            skipped += 1
            continue
        amount = r[ix['TXN_AMOUNT']] or 0
        total += float(amount)
        w.writerow([
            wallet,
            with_acc,
            (r[ix['TXN_TYPE']] or '').strip(),
            (r[ix['TXN_MODE']] or '').strip().upper(),
            r[ix['TXN_COUNT']] or 0,
            amount,
        ])
        n += 1

print(f'wrote {out}')
print(f'  rows          {n:,}  (skipped {skipped} with no SUSPECTED_WALLET)')
print(f'  TXN_AMOUNT    {total:,.2f} tk  = {total / 1e7:.2f} Crore')
