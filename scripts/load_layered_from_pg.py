"""
KGN4j - Layered Trail : PostgreSQL -> Neo4j, no CSV in between

Usage (from the project root, Neo4j running):
    python scripts/load_layered_from_pg.py

Reads the `layered` table straight from PostgreSQL and writes it into Neo4j,
then builds the graph (cypher/layered/01_build_layered_graph.cypher).

Why a script and not apoc.load.jdbc: on Neo4j 2026.08.1 apoc.load.jdbc
lives in APOC Extended, and there is no Extended release for 2026.08 (see
docs/TROUBLESHOOTING.md). This script does the same job from outside.

Connection (defaults in brackets; override with these environment
variables):
    PGHOST [localhost]  PGPORT [5432]  PGDATABASE [neo4j]  PGUSER [postgres]
    PGTABLE [public.layered]
    NEO4J_HTTP [http://localhost:7474]  NEO4J_DATABASE [neo4j]  NEO4J_USER [neo4j]
Passwords: PGPASSWORD and NEO4J_PASSWORD, or typed in when asked (not shown,
not stored).

Needs: pip install psycopg   (already installed here). Neo4j is reached
over its HTTP Query API, so no Neo4j driver is needed.

SEPARATE PIPELINE: it only deletes and creates :LyrTxn (rows), :LNet /
:LFLOW / :LLegend (graph). Nothing else in Neo4j or PostgreSQL changes -
PostgreSQL is only read.
"""
import base64
import getpass
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'cypher' / 'layered' / '01_build_layered_graph.cypher'

PG = {
    'host': os.environ.get('PGHOST', 'localhost'),
    'port': int(os.environ.get('PGPORT', '5432')),
    'dbname': os.environ.get('PGDATABASE', 'neo4j'),
    'user': os.environ.get('PGUSER', 'postgres'),
}
PG_TABLE = os.environ.get('PGTABLE', 'public.layered')
NEO4J_HTTP = os.environ.get('NEO4J_HTTP', 'http://localhost:7474').rstrip('/')
NEO4J_DB = os.environ.get('NEO4J_DATABASE', 'neo4j')
NEO4J_USER = os.environ.get('NEO4J_USER', 'neo4j')

LOAD = """
UNWIND $rows AS row
CREATE (r:LyrTxn {txn_id: row.txn_id})
SET r.row_no    = row.row_no,
    r.tag       = row.tag,
    r.layer     = row.layer,
    r.from_acc  = row.from_acc,
    r.with_acc  = row.with_acc,
    r.with_info = row.with_info,
    r.txn_type  = row.txn_type,
    r.channel   = row.channel,
    r.status    = row.status,
    r.dc        = row.dc,
    r.amount    = row.amount,
    r.post_blc  = row.post_blc,
    r.ts_text   = row.ts_text,
    r.ts        = localdatetime(row.ts)
"""


def num(v):
    """'49,995.00', ' 800.00 ', 250, None -> float (None stays None)."""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = re.sub(r'[,\s]', '', str(v))
    return float(s) if s else None


def text(v):
    return '' if v is None else str(v).strip()


def read_postgres(password):
    schema, _, table = PG_TABLE.rpartition('.')
    ident = sql.Identifier(schema, table) if schema else sql.Identifier(table)
    with psycopg.connect(password=password, connect_timeout=10, **PG) as conn:
        cur = conn.execute(sql.SQL('SELECT * FROM {}').format(ident))
        cols = [d.name.lower() for d in cur.description]
        rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    out = []
    for i, r in enumerate(rows, start=1):
        txn_id = text(r.get('txn_id'))
        if not txn_id:
            continue
        ts = r.get('approval_datetime')
        if ts is None:
            sys.exit(f'row {i} ({txn_id}): APPROVAL_DATETIME is empty')
        if isinstance(ts, str):  # a text column: "2026-10-16 12:07:28.9430000"
            head, _, frac = ts.strip().partition('.')
            ts_iso = head.replace(' ', 'T') + ('.' + frac[:6] if frac else '')
        else:  # a timestamp column
            ts_iso = ts.isoformat()
        out.append({
            'row_no': i,
            'txn_id': txn_id,
            'tag': text(r.get('txn_sl_tag')),
            'layer': int(num(r.get('layer'))),
            'from_acc': text(r.get('txn_from')),
            'with_acc': text(r.get('txn_with')),
            'with_info': text(r.get('txn_with_info')),
            'txn_type': text(r.get('txn_type')),
            'channel': text(r.get('channel')),
            'status': text(r.get('status')).upper(),
            'dc': text(r.get('txn_type_d_c')).upper(),
            'amount': num(r.get('txn_amt')) or 0.0,
            'post_blc': num(r.get('post_blc')),
            'ts': ts_iso,
            'ts_text': ts_iso.replace('T', ' ')[:23],
        })
    return out


class Neo4j:
    def __init__(self, password):
        token = base64.b64encode(f'{NEO4J_USER}:{password}'.encode()).decode()
        self.headers = {'Content-Type': 'application/json', 'Accept': 'application/json',
                        'Authorization': f'Basic {token}'}
        self.url = f'{NEO4J_HTTP}/db/{NEO4J_DB}/query/v2'

    def run(self, statement, parameters=None):
        body = json.dumps({'statement': statement, 'parameters': parameters or {}}).encode()
        req = urllib.request.Request(self.url, data=body, headers=self.headers, method='POST')
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                res = json.load(resp)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors='replace')
            raise SystemExit(f'Neo4j error ({e.code}):\n{detail}\n\nin statement:\n{statement[:400]}')
        except urllib.error.URLError as e:
            raise SystemExit(f'Cannot reach Neo4j at {NEO4J_HTTP} - is it running? ({e.reason})')
        if res.get('errors'):
            raise SystemExit(f'Neo4j error: {res["errors"]}\n\nin statement:\n{statement[:400]}')
        data = res.get('data', {})
        return data.get('fields', []), data.get('values', [])


def build_statements(path):
    """Split a .cypher file into statements; `:param x => v;` lines become parameters."""
    params, statements, current = {}, [], []
    for line in path.read_text(encoding='utf-8').splitlines():
        stripped = line.strip()
        if stripped.startswith('//') or not stripped:
            continue
        m = re.match(r':param\s+(\w+)\s*=>\s*(.+?);\s*$', stripped)
        if m:
            params[m.group(1)] = json.loads(m.group(2))
            continue
        current.append(line)
        if stripped.endswith(';'):
            statements.append('\n'.join(current).rstrip().rstrip(';'))
            current = []
    if current:
        statements.append('\n'.join(current))
    return params, statements


def show(fields, values):
    if not fields or not values:
        return
    print('  ' + ' | '.join(fields))
    for v in values:
        print('  ' + ' | '.join('' if x is None else str(x) for x in v))


def main():
    pg_pw = os.environ.get('PGPASSWORD') or getpass.getpass(
        f'PostgreSQL password for {PG["user"]}@{PG["host"]}/{PG["dbname"]}: ')
    rows = read_postgres(pg_pw)
    print(f'read {len(rows)} rows from {PG["dbname"]}.{PG_TABLE}')
    if not rows:
        sys.exit('nothing to load')

    neo_pw = os.environ.get('NEO4J_PASSWORD') or getpass.getpass(f'Neo4j password for {NEO4J_USER}: ')
    neo = Neo4j(neo_pw)

    # load the rows (only :LyrTxn is deleted)
    neo.run('MATCH (r:LyrTxn) DETACH DELETE r')
    for stmt in ['CREATE INDEX lyrtxn_id IF NOT EXISTS FOR (r:LyrTxn) ON (r.txn_id)',
                 'CREATE INDEX lyrtxn_from IF NOT EXISTS FOR (r:LyrTxn) ON (r.tag, r.layer, r.from_acc)',
                 'CREATE INDEX lyrtxn_with IF NOT EXISTS FOR (r:LyrTxn) ON (r.tag, r.layer, r.with_acc)']:
        neo.run(stmt)
    for i in range(0, len(rows), 5000):
        neo.run(LOAD, {'rows': rows[i:i + 5000]})
    print('loaded into Neo4j, one line per trail and layer:')
    show(*neo.run("""
        MATCH (r:LyrTxn)
        RETURN r.tag AS tag, r.layer AS layer, count(*) AS rows,
               sum(CASE WHEN toUpper(r.txn_type) = 'P2P' THEN 1 ELSE 0 END) AS p2p_rows,
               round(sum(r.amount), 2) AS amount
        ORDER BY tag, layer"""))

    # build the graph
    params, statements = build_statements(BUILD)
    print(f'\nbuilding the graph ({BUILD.relative_to(ROOT)}, {len(statements)} statements)')
    result = None
    for stmt in statements:
        result = neo.run(stmt, params)
    print('check - traced money kept by people = layer-1 amount:')
    show(*result)


if __name__ == '__main__':
    main()
