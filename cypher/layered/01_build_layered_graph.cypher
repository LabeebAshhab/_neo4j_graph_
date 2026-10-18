// =====================================================================
// KGN4j - Layered Trail : trace the money and build the graph
//
// Run by scripts/load_layered_from_pg.py right after it loads the rows,
// or on its own in Neo4j Browser to rebuild the graph from the :LyrTxn
// rows already in the database.
//
// SEPARATE PIPELINE. Every graph node carries :LNet and every relationship
// is :LFLOW; the legend nodes carry :LLegend. The first statements delete
// only those (and reset the traced figures on :LyrTxn), so :Nav, :Canon,
// :SNet, :SusRow, :Transaction and :Account are never touched.
//
// P2P ONLY. Rows whose TXN_TYPE is not P2P (Cash Out, Top Up, Transfer
// Money to card, ...) are left out of the trace and the graph entirely.
//
// THE RULE (same as scripts/check_layered_trace.py)
//   * A layer-1 P2P transfer is traced in full - it is the money followed.
//   * A layer-L P2P transfer out of account X (L >= 2) can only carry
//     money X received by P2P in layer L-1 of the same TXN_SL_TAG. X's
//     transfers are walked in time order (FIFO) against that money:
//         balance += every traced layer-(L-1) P2P amount X received
//         each layer-L P2P transfer takes min(amount, balance)
//     X received 50 and sent 100 -> 50 is traced, 50 is MINUS (orange).
//     X sends to several accounts -> the earliest are traced first.
//   * Nobody passes on more than they received, so the traced money kept
//     by every account adds up to the layer-1 amount.
//
// WHAT IS DRAWN (click to open one level at a time)
//   start     : every source and the person it paid in layer 1
//   click a person -> the people that person paid by P2P (next layer)
//   click again    -> keeps the path open and opens the next level
//   click a LAYER header -> closes everything again
//
//   (SRC) hexagon  - TXN_FROM of layer 1: where the money starts
//   (n)   circle   - a person who passed money on (click to open),
//                    coloured by the layer they received it in
//   [n]   square   - a person who passed nothing on by P2P: the trail
//                    ends there, same colour scheme
//   inside       = traced amount received
//   beside       = account number; under it "pays N people", "kept X",
//                  "-Y not traced"
//   ORANGE node  = a person with a minus: only part of what they got
//                  counts, or they sent more than they got
//   arrow        = grey: fully traced; ORANGE: part of it is minus,
//                  caption "traced  (-minus)"
//
// A node is one account AT ONE LAYER of one trail: an account that turns
// up in two layers is drawn twice (the Selected card lists the others).
// Positions are pin_x / pin_y (x right, y DOWN), always floats.
// Needs neodash-patches/kgn4j-suspect-graph.patch (shapes, outside labels,
// pinned positions) - already applied for the Suspect Network.
// =====================================================================

// respect_time - true: a transfer can only carry money that had ALREADY
//                arrived (by APPROVAL_DATETIME). false: everything X got
//                in layer L-1 counts, whenever it arrived; still FIFO.
// col_gap      - distance between layer columns
// row_gap      - distance between two leaves of a tree
// tree_gap     - extra space between two trails
:param respect_time => true;
:param col_gap      => 300.0;
:param row_gap      => 46.0;
:param tree_gap     => 90.0;


// 2.0  Drop the previous graph and legend; reset the traced figures.
MATCH (n) WHERE n:LNet OR n:LLegend DETACH DELETE n;

CREATE INDEX lnet_key IF NOT EXISTS FOR (n:LNet) ON (n.key);
CALL db.awaitIndexes(300);

MATCH (r:LyrTxn)
SET r.p2p      = toUpper(r.txn_type) = 'P2P',
    r.traced   = CASE WHEN r.layer = 1 AND toUpper(r.txn_type) = 'P2P' THEN r.amount ELSE null END,
    r.excess   = null,
    r.orphan   = false,
    r.from_key = r.tag + '|' + toString(r.layer - 1) + '|' + r.from_acc,
    r.to_key   = r.tag + '|' + toString(r.layer)     + '|' + r.with_acc;


// 2.1  Trace, one layer at a time (layer L needs layer L-1 finished;
//      each CALL sees what the previous one wrote).
//      Events of one (trail, sender): its layer-(L-1) P2P inflows and its
//      layer-L P2P outflows, in time order, inflows first on a tie.
MATCH (r:LyrTxn {p2p: true})
WITH max(r.layer) AS top
UNWIND range(2, top) AS L
CALL {
  WITH L
  MATCH (o:LyrTxn {layer: L, p2p: true})
  WITH L, o.tag AS tag, o.from_acc AS acc, collect(o) AS outs
  OPTIONAL MATCH (i:LyrTxn {tag: tag, layer: L - 1, with_acc: acc, p2p: true})
  WITH outs, collect(i) AS ins
  WITH outs, size(ins) = 0 AS orphan,
       [x IN ins  | {t: CASE WHEN $respect_time THEN x.ts ELSE localdatetime('0001-01-01T00:00:00') END,
                     o: 0, id: x.txn_id, amt: coalesce(x.traced, 0.0), n: x}] +
       [x IN outs | {t: x.ts, o: 1, id: x.txn_id, amt: x.amount, n: x}] AS ev
  CALL {
    WITH ev
    UNWIND ev AS e
    WITH e ORDER BY e.t, e.o, e.id
    RETURN collect(e) AS sorted
  }
  WITH orphan, reduce(s = {bal: 0.0, take: []}, e IN sorted |
         CASE WHEN e.o = 0
              THEN {bal: s.bal + e.amt, take: s.take}
              ELSE {bal:  s.bal - CASE WHEN e.amt < s.bal THEN e.amt ELSE s.bal END,
                    take: s.take + [[e.n, CASE WHEN e.amt < s.bal THEN e.amt ELSE s.bal END]]}
         END) AS s
  UNWIND s.take AS t
  WITH orphan, t[0] AS n, t[1] AS traced
  SET n.traced = traced, n.orphan = orphan
  RETURN count(*) AS traced_rows
}
RETURN L AS layer, traced_rows;

MATCH (r:LyrTxn {p2p: true})
SET r.excess = r.amount - r.traced;


// 2.2  Nodes. Receivers: one per (trail, layer, TXN_WITH) of a P2P row.
//      Senders that received nothing by P2P in the layer before: the
//      layer-1 senders are the sources; any other is an orphan (its rows
//      trace 0).
MATCH (r:LyrTxn {p2p: true})
WITH DISTINCT r.to_key AS key, r.tag AS tag, r.layer AS layer, r.with_acc AS acc
CREATE (n:LNet:LAccount {key: key})
SET n.tag = tag, n.layer = layer, n.acc = acc, n.orphan = false;

MATCH (r:LyrTxn {p2p: true})
WHERE NOT EXISTS { MATCH (:LNet {key: r.from_key}) }
WITH DISTINCT r.from_key AS key, r.tag AS tag, r.layer - 1 AS layer, r.from_acc AS acc
CALL apoc.create.node(['LNet', CASE WHEN layer = 0 THEN 'LSource' ELSE 'LAccount' END], {key: key})
YIELD node AS n
SET n.tag = tag, n.layer = layer, n.acc = acc, n.orphan = layer > 0;


// 2.3  Arrows: the P2P transfers from one node to another, summed.
MATCH (r:LyrTxn {p2p: true})
WITH r.from_key AS fk, r.to_key AS tk, r.tag AS tag, r.layer AS layer,
     sum(r.traced) AS traced, sum(r.amount) AS sent, count(*) AS txns, min(r.ts) AS first_ts
MATCH (a:LNet {key: fk}), (b:LNet {key: tk})
CREATE (a)-[:LFLOW {tag: tag, layer: layer, amount: traced, sent: sent, excess: sent - traced,
                    txn_count: txns, first_ts: first_ts}]->(b);


// 2.4  Totals on every node.
//      traced_in  - traced money received (a source: everything it sent)
//      kept       - traced_in - traced_out: what stayed with the person
//      excess     - sent beyond the traced money: the minus
//      pays       - how many people it paid by P2P (the next layer)
MATCH (n:LNet)
CALL {
  WITH n
  OPTIONAL MATCH ()-[i:LFLOW]->(n)
  RETURN coalesce(sum(i.amount), 0.0) AS tin, coalesce(sum(i.sent), 0.0) AS rin,
         coalesce(sum(i.txn_count), 0) AS txns_in
}
CALL {
  WITH n
  OPTIONAL MATCH (n)-[o:LFLOW]->(c)
  RETURN coalesce(sum(o.amount), 0.0) AS tout, coalesce(sum(o.sent), 0.0) AS sout,
         coalesce(sum(o.txn_count), 0) AS txns_out, count(DISTINCT c) AS pays
}
WITH n, CASE WHEN n:LSource THEN tout ELSE tin END AS traced_in, rin, tout, sout, txns_in, txns_out, pays
SET n.traced_in  = traced_in,
    n.received   = rin,
    n.traced_out = tout,
    n.sent       = sout,
    n.excess     = sout - tout,
    n.kept       = traced_in - tout,
    n.txns_in    = txns_in,
    n.txns_out   = txns_out,
    n.pays       = pays;

// the other layers the same account shows up in, within the trail
MATCH (n:LNet)
OPTIONAL MATCH (m:LNet {tag: n.tag, acc: n.acc}) WHERE m.layer <> n.layer
WITH n, collect(DISTINCT m.layer) AS others
SET n.also_in_layers = apoc.coll.sort(others);


// 2.5  Tree. Each node hangs under ONE parent - the arrow in that carried
//      the most traced money - and under it, siblings are in time order
//      (so the FIFO cut-off reads top to bottom).
MATCH (p:LNet)-[e:LFLOW]->(n:LNet)
WITH n, p, e ORDER BY e.amount DESC, e.sent DESC, e.first_ts ASC
WITH n, collect({p: p, e: e})[0] AS top
WITH n, top.p AS p, top.e AS e
SET e.primary = true, n.parent_key = p.key;

MATCH (p:LNet)-[e:LFLOW {primary: true}]->(c:LNet)
WITH p, c, e ORDER BY e.first_ts, c.key
WITH p, collect(c) AS kids
UNWIND range(0, size(kids) - 1) AS i
WITH kids[i] AS c, i
SET c.sib = i;

// roots: the sources, plus any orphan sender; one tree each
MATCH (r:LNet) WHERE r.parent_key IS NULL
WITH r ORDER BY coalesce(toIntegerOrNull(r.tag), 0), r.tag, r.layer, r.sent DESC
WITH collect(r) AS roots
UNWIND range(0, size(roots) - 1) AS i
WITH roots[i] AS r, i
SET r.tree = i, r.sib = i;

// path  = the sibling numbers from the root down, "00002/00000/00003/"
// chain = the keys from the root down to the node: a click opens the
//         children of every node on the clicked node's chain
MATCH p = (r:LNet)(()-[:LFLOW {primary: true}]->())*(n:LNet)
WHERE r.parent_key IS NULL
SET n.tree  = r.tree,
    n.path  = reduce(s = '', x IN nodes(p) | s + right('00000' + toString(x.sib), 5) + '/'),
    n.chain = [x IN nodes(p) | x.key];


// 2.6  Positions. Only one path is open at a time, so a column never
//      shows more than one group of siblings: every person's payees fan
//      out in the next column, centred on that person. Trails are stacked
//      top to bottom, each with room for its own layer-1 fan.
//      Fixed per node, so opening a level never moves what is on screen.
MATCH (r:LNet) WHERE r.parent_key IS NULL
OPTIONAL MATCH (r)-[:LFLOW {primary: true}]->(k)
WITH r, count(k) AS kids ORDER BY r.tree
WITH collect({r: r, h: CASE WHEN kids > 1 THEN kids ELSE 1 END * $row_gap + $tree_gap}) AS trees
UNWIND range(0, size(trees) - 1) AS i
WITH trees[i].r AS r, reduce(y = 0.0, t IN trees[0 .. i] | y + t.h) + (trees[i].h - $tree_gap) / 2.0 AS y
SET r.pin_x = toFloat(r.layer) * $col_gap,
    r.pin_y = y;

MATCH (n:LNet)
WITH max(n.layer) AS top
UNWIND range(1, top) AS L
CALL {
  WITH L
  MATCH (p:LNet)-[:LFLOW {primary: true}]->(c:LNet {layer: L})
  WHERE p.pin_y IS NOT NULL
  WITH p, count(c) AS n, collect(c) AS kids
  UNWIND kids AS c
  SET c.pin_x = toFloat(c.layer) * $col_gap,
      c.pin_y = p.pin_y + (toFloat(c.sib) - (n - 1) / 2.0) * $row_gap
  RETURN count(*) AS placed
}
RETURN L AS layer, placed;

// column headers: SOURCE, LAYER 1 ... LAYER n, above the top tree
MATCH (n:LNet)
WITH max(n.layer) AS top, min(n.pin_y) AS y0
UNWIND range(0, top) AS L
CALL {
  WITH L
  MATCH ()-[e:LFLOW {layer: L}]->()
  RETURN sum(e.amount) AS traced, sum(e.sent) AS sent
}
CREATE (h:LNet:LHeader {key: 'hdr|' + toString(L)})
SET h.layer  = L,
    h.name   = CASE WHEN L = 0 THEN 'SOURCE' ELSE 'LAYER ' + toString(L) END,
    h.amount = CASE WHEN L = 0 THEN null ELSE traced END,
    h.sent   = CASE WHEN L = 0 THEN null ELSE sent END,
    h.chain  = [],
    h.pin_x  = toFloat(L) * $col_gap,
    h.pin_y  = y0 - 80.0;


// 2.7  Arrow captions: traced amount, the minus in brackets. Width
//      follows the traced amount, relative to the trail's layer-1 amount.
MATCH (a:LNet)-[e:LFLOW]->(b:LNet)
MATCH (s:LSource {tag: e.tag})
WITH a, b, e, sum(s.sent) AS start
SET e.name = apoc.number.format(e.amount, '#,##0.##')
             + CASE WHEN e.excess > 0.005 THEN '  (-' + apoc.number.format(e.excess, '#,##0.##') + ')' ELSE '' END
             + CASE WHEN e.txn_count > 1 THEN '  x' + toString(e.txn_count) ELSE '' END,
    e.amount_text = e.name,
    e.color = CASE WHEN e.excess > 0.005 THEN '#F08A24' ELSE '#9AA8B6' END,
    e.width = round(0.8 + 4.2 * sqrt(CASE WHEN start > 0 THEN e.amount / start ELSE 0 END), 2);


// 2.8  STYLE - shape, colour, captions and a plain-English `role`. The
//      legend (2.9) uses the same values.
//        Source                 hexagon, wine, white text
//        Person who paid on     circle, one colour per layer, white text
//        Person - trail ends    square, the same layer colour
//        Column header          box, pale grey
//      ORANGE is kept for the minus only: an arrow that carries a minus,
//      and a person with a minus on either side - only part of what they
//      got counts, or they sent more than they got (shape unchanged).
MATCH (n:LNet)
WITH n,
     ['#3D6FD1', '#2E9A74', '#8462C8', '#C9558A', '#5F7182', '#2F8FA3', '#8A6D3B'] AS layer_colors,
     [p IN [
        CASE WHEN n.pays > 0 THEN 'pays ' + toString(n.pays) + CASE WHEN n.pays = 1 THEN ' person' ELSE ' people' END END,
        CASE WHEN n:LAccount AND n.kept > 0.005 THEN 'kept ' + apoc.number.format(n.kept, '#,##0.##') END,
        CASE WHEN n:LAccount AND n.received - n.traced_in > 0.005
             THEN 'got ' + apoc.number.format(n.received, '#,##0.##') + ', -'
                  + apoc.number.format(n.received - n.traced_in, '#,##0.##') + ' not traced' END,
        CASE WHEN n.excess > 0.005 THEN 'sent -' + apoc.number.format(n.excess, '#,##0.##') + ' not traced' END,
        CASE WHEN n.orphan THEN 'no P2P in from layer ' + toString(n.layer - 1) END
      ] WHERE p IS NOT NULL] AS notes
WITH n, notes,
     CASE
       WHEN n:LHeader THEN ['box', '#E4E8EC', null, n.name, '',
                            'Column - click to close every level']
       WHEN n:LSource THEN ['hexagon', '#7A1F3D', '#FFFFFF', apoc.number.format(n.sent, '#,##0.##'),
                            'start | TXN_SL_TAG ' + n.tag,
                            'Source - sends the layer-1 money (TXN_SL_TAG ' + n.tag + ')']
       WHEN n.pays > 0 THEN ['circle', layer_colors[(n.layer - 1) % size(layer_colors)], '#FFFFFF',
                            apoc.number.format(n.traced_in, '#,##0.##'), '',
                            'Layer ' + toString(n.layer) + ' person - click to see who they paid']
       ELSE ['box', layer_colors[(n.layer - 1) % size(layer_colors)], '#FFFFFF',
             apoc.number.format(n.traced_in, '#,##0.##'), '',
             'Layer ' + toString(n.layer) + ' person - paid nobody on by P2P (trail ends)']
     END AS st
WITH n, st, notes,
     CASE WHEN size(st[3]) * 2.5 + 4 > 9 THEN size(st[3]) * 2.5 + 4 ELSE 9.0 END
       + CASE WHEN n:LSource THEN 3 ELSE 0 END AS radius
SET n.shape      = st[0],
    // orange: a minus on the money in (only part of what they got counts)
    // or on the money out (they sent more than they got)
    n.color      = CASE WHEN n:LAccount AND (n.excess > 0.005 OR n.received - n.traced_in > 0.005)
                        THEN '#F08A24' ELSE st[1] END,
    n.text_color = st[2],
    n.name       = st[3],
    n.role       = st[5],
    n.outer      = CASE WHEN n:LHeader THEN '' ELSE n.acc END,
    n.outer2     = reduce(s = st[4], p IN notes | CASE WHEN s = '' THEN p ELSE s + ' | ' + p END),
    n.click      = n.key,
    n.size       = round((radius / 4.0) ^ 2, 2),
    // read by the patched tooltip
    n.amount        = CASE WHEN n:LHeader THEN n.amount ELSE n.traced_in END,
    n.credit_amount = n.received,
    n.debit_amount  = n.sent,
    n.txn_count     = CASE WHEN n:LHeader THEN null ELSE n.txns_in + n.txns_out END,
    n.wallet_count  = n.pays;


// 2.9  The legend card: the same shapes and colours, with what they mean.
UNWIND [
  ['hexagon', '#7A1F3D', '#FFFFFF', 'SRC', 'Source - sends the layer-1 money'],
  ['circle',  '#3D6FD1', '#FFFFFF', 'L1',  'Layer 1 person'],
  ['circle',  '#2E9A74', '#FFFFFF', 'L2',  'Layer 2 person'],
  ['circle',  '#8462C8', '#FFFFFF', 'L3',  'Layer 3 person'],
  ['circle',  '#C9558A', '#FFFFFF', 'L4',  'Layer 4 person'],
  ['circle',  '#5F7182', '#FFFFFF', 'L5',  'Layer 5 person'],
  ['circle',  '#9AA8B6', '#FFFFFF', 'n',   'Circle - paid others on (click to open)'],
  ['box',     '#9AA8B6', '#FFFFFF', 'n',   'Square - paid nobody on: trail ends'],
  ['circle',  '#F08A24', '#FFFFFF', '-',   'Orange circle / square - a minus in or out'],
  ['diamond', '#9AA8B6', null,      'tk',  'Grey arrow - fully traced'],
  ['diamond', '#F08A24', null,      '-',   'Orange arrow (-x) - sent more than came in; x is not counted'],
  ['box',     '#E4E8EC', null,      'LAYER', 'Column header - click to close all']
] AS e
WITH collect(e) AS rows
UNWIND range(0, size(rows) - 1) AS i
WITH i, rows[i] AS e
CREATE (l:LLegend {key: 'lyr-legend:' + toString(i)})
SET l.shape = e[0], l.color = e[1], l.text_color = e[2], l.name = e[3], l.outer = e[4], l.rank = i,
    l.pin_x = 0.0, l.pin_y = toFloat(i * 28),
    l.size = round(((CASE WHEN size(e[3]) * 2.5 + 4 > 9 THEN size(e[3]) * 2.5 + 4 ELSE 9.0 END) / 4.0) ^ 2, 2);


// 2.10 Report - per trail: the layer-1 P2P amount and the traced money
//      kept by every person. KEPT must equal START (CHECK = OK).
MATCH (s:LSource)
WITH s.tag AS tag, sum(s.sent) AS start
MATCH (n:LAccount {tag: tag})
WITH tag, start, sum(n.kept) AS kept, max(n.layer) AS layers
RETURN tag, layers, round(start, 2) AS start, round(kept, 2) AS kept_by_people,
       CASE WHEN abs(kept - start) < 0.005 THEN 'OK' ELSE 'MISMATCH' END AS check
ORDER BY coalesce(toIntegerOrNull(tag), 0), tag;
