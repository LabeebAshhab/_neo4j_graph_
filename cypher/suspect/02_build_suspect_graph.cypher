// =====================================================================
// KGN4j - Suspect Network, step 3 : build the graph the dashboard draws
//
// SEPARATE PIPELINE. Every graph node carries :SNet and every relationship
// is :SFLOW; the legend nodes carry :SLegend. The first statement deletes
// only those, so :Nav (Pathao Pay drill-down), :Canon (Money Trail),
// :Transaction, :Account and :SusRow are never touched.
//
// WHAT IS ON SCREEN
//   A node with no `parent_key` is always drawn (the base graph). Every
//   other node is drawn when its parent is on the clicked node's `chain`
//   (the clicked node and its ancestors) - so a click opens one level and
//   clicking any base node closes everything again.
//
//   BASE, typed in from the hand notes and the status table:
//     (Agent) 01979603374 --Cash IN 5090--> (TR) 01333157844 --P2P 5085--> (Customer) 01961932548
//     (Customer) --total TXN Wallet--> (1872)
//     (1872) --Merchant--> (1) Suspended
//            --Agent-----> (1082) --> (312) Active, (770) Suspended
//            --Customer--> (789)  --> (340) Suspended, (441) Active, (8) Deleted
//                                 --TXN_AMOUNT--> (90 Cr)
//     (84930) --Customer--> (60131) --> ACTIVE / PRELIMINARY_ACCOUNT / DELETED / SUSPENDED
//             --Merchant--> (533)   --> SUSPENDED / ACTIVE
//             --Uddokta---> (25218) --> SUSPENDED / ACTIVE
//   BASE, computed from the sheet (:SusRow):
//     (90 Cr) --txn_with_wallet--> (84930) Wallet      distinct TXN_WITH_ACC
//     (84930) --90.44 Crore tk--> (789)
//     (789)   --txn_type--> (TXN_TYPE)                 distinct transaction types
//     (TXN_TYPE) --amount--> half ring: the top 10 transaction types,
//                           (More types) = the smaller ones, and
//                           (Others) = all the *-SERVICE_FEE types together
//   ON CLICK (a radial tree round TXN_TYPE - each level on its own circle,
//            a node's children as an arc of the next circle, centred on it):
//     Others (service fees) -> each service fee type (its total fee)
//     More types            -> each smaller transaction type
//     a type / fee type     -> its top suspected wallets + Others
//     a suspected wallet    -> its top TXN_WITH_ACC counterparties + Others
//                              (arrow in = CREDIT, arrow out = DEBIT)
//
// TEXT ON A NODE
//   name   - inside the shape
//   outer  - beside it; along the spoke (label_angle) on the radial part
//   outer2 - a smaller second line: the amount, on the radial part (its
//            spokes carry no caption - a caption half way along a spoke
//            sits where the inner circle's labels are)
// SHAPE AND COLOUR for the whole graph are set in one place, section
// 3.10, and the legend (3.11) uses the same values.
// Positions are pin_x / pin_y in graph units (x right, y DOWN), always
// floats - NeoDash mis-converts negative Neo4j integers.
// Needs neodash-patches/kgn4j-suspect-graph.patch.
// =====================================================================

// top_wallets        - suspected wallets shown when a type is clicked
// top_counterparties - TXN_WITH_ACC shown when a wallet is clicked
// ring_types         - transaction types on the ring (the rest: "More types")
// hub_x / hub_y      - where the TXN_TYPE node sits
// ring_arc_deg       - the half ring of types, opening to the right
// radii              - RADIAL TREE: every level sits on its own circle round
//                      TXN_TYPE - level 1 = the ring, level 2 = what a ring
//                      node opens, and so on. Each circle starts beyond the
//                      longest label of the one inside it, so spokes and
//                      labels never cross.
// radial_spacing     - neighbours on the same circle at least this far apart
:param top_wallets        => 10;
:param top_counterparties => 10;
:param ring_types         => 10;
:param hub_x              => 380.0;
:param hub_y              => 40.0;
:param ring_arc_deg       => 160.0;
:param radii              => [200.0, 500.0, 770.0, 930.0, 1110.0];
:param radial_spacing     => 42.0;


// 3.0  Drop the previous suspect graph and legend.
MATCH (n) WHERE n:SNet OR n:SLegend DETACH DELETE n;


// 3.1  Base nodes from the hand notes. `acct` is the account type the
//      node stands for - it decides the node's colour in 3.10.
UNWIND [
  {key: 'agent',     name: 'Agent',    outer: '01979603374', x: 10,   y: -230, acct: 'Agent'},
  {key: 'tr',        name: 'TR',       outer: '01333157844', x: -130, y: -190, acct: 'TR'},
  {key: 'customer',  name: 'Customer', outer: '01961932548', x: 10,   y: -150, acct: 'Customer'},
  {key: 'w1872',     name: '1872',     outer: '',            x: 10,   y: -60},
  {key: 'merchant1', name: '1',        outer: 'Suspended',   x: -130, y: -20,  status: 'SUSPENDED'},
  {key: 'agent1082', name: '1082',     outer: '',            x: -80,  y: 50,   acct: 'Agent'},
  {key: 'agent312',  name: '312',      outer: 'Active',      x: -150, y: 150,  status: 'ACTIVE'},
  {key: 'agent770',  name: '770',      outer: 'Suspended',   x: -200, y: 110,  status: 'SUSPENDED'},
  {key: 'cust789',   name: '789',      outer: '',            x: 70,   y: 50,   acct: 'Customer'},
  {key: 'cust340',   name: '340',      outer: 'Suspended',   x: 100,  y: 150,  status: 'SUSPENDED'},
  {key: 'cust441',   name: '441',      outer: 'Active',      x: 170,  y: 115,  status: 'ACTIVE'},
  {key: 'cust8',     name: '8',        outer: 'Deleted',     x: 150,  y: -15,  status: 'DELETED'},
  {key: 'amount',    name: '90 Cr',    outer: '',            x: -40,  y: 230}
] AS s
CREATE (n:SNet:SStatic {key: s.key})
SET n.name   = s.name,
    n.outer  = s.outer,
    n.status = s.status,
    n.acct   = s.acct,
    n.pin_x  = toFloat(s.x),
    n.pin_y  = toFloat(s.y);

UNWIND [
  {a: 'agent',     b: 'tr',        name: 'Cash IN 5090', amount: 5090},
  {a: 'tr',        b: 'customer',  name: 'P2P 5085',     amount: 5085},
  {a: 'customer',  b: 'w1872',     name: 'total TXN Wallet'},
  {a: 'w1872',     b: 'merchant1', name: 'Merchant'},
  {a: 'w1872',     b: 'agent1082', name: 'Agent'},
  {a: 'w1872',     b: 'cust789',   name: 'Customer'},
  {a: 'agent1082', b: 'agent312',  name: ''},
  {a: 'agent1082', b: 'agent770',  name: ''},
  {a: 'cust789',   b: 'cust340',   name: ''},
  {a: 'cust789',   b: 'cust441',   name: ''},
  {a: 'cust789',   b: 'cust8',     name: ''},
  {a: 'cust789',   b: 'amount',    name: 'TXN_AMOUNT'}
] AS e
MATCH (a:SNet {key: e.a}), (b:SNet {key: e.b})
CREATE (a)-[:SFLOW {name: e.name, amount: e.amount}]->(b);


// 3.2  (90 Cr) --txn_with_wallet--> (84930) --90.44 Crore tk--> (789).
//      "90 Cr" stays as written in the notes; the sheet's own total is
//      kept on it as `data_total` for hover.
MATCH (amt:SNet {key: 'amount'}), (c:SNet {key: 'cust789'})
CALL {
  MATCH (r:SusRow)
  RETURN count(DISTINCT r.with_acc) AS with_wallets, count(DISTINCT r.wallet) AS suspected,
         sum(r.amount) AS total, sum(r.txn_count) AS txns
}
SET amt.data_total = total
CREATE (w:SNet:SWallets {key: 'with_wallets'})
SET w.name = toString(with_wallets), w.outer = 'Wallet',
    w.pin_x = -190.0, w.pin_y = 230.0,
    w.with_wallets = with_wallets, w.suspected_wallets = suspected, w.total = total, w.txn_count = txns
CREATE (amt)-[:SFLOW {name: 'txn_with_wallet', amount: total}]->(w)
CREATE (w)-[:SFLOW {amount: total, fmt: true}]->(c);


// 3.3  (84930) broken down by account type and status - STATIC, typed in
//      from the ACCOUNT_TYPE / STATUS / WALLET_COUNT table. Group numbers
//      are the sums of their statuses (together 85,882 - 952 more than the
//      84,930 distinct TXN_WITH_ACC in the sheet; drawn as given).
//      Left of the drawing: groups at x = -400, statuses at x = -620.
UNWIND [
  {type: 'Customer', y: 40.0, rows: [
     {status: 'ACTIVE',              n: 55545},
     {status: 'PRELIMINARY_ACCOUNT', n: 95},
     {status: 'DELETED',             n: 52},
     {status: 'SUSPENDED',           n: 4439}]},
  {type: 'Merchant', y: 180.0, rows: [
     {status: 'SUSPENDED',           n: 237},
     {status: 'ACTIVE',              n: 296}]},
  {type: 'Uddokta',  y: 300.0, rows: [
     {status: 'SUSPENDED',           n: 18034},
     {status: 'ACTIVE',              n: 7184}]}
] AS g
MATCH (w:SNet {key: 'with_wallets'})
WITH w, g, reduce(s = 0, r IN g.rows | s + r.n) AS total
CREATE (t:SNet:SStatic {key: 'ww:' + g.type})
SET t.name = toString(total), t.outer = g.type, t.account_type = g.type, t.wallet_count = total,
    t.acct = CASE g.type WHEN 'Uddokta' THEN 'Agent' ELSE g.type END,
    t.pin_x = -400.0, t.pin_y = g.y
CREATE (w)-[:SFLOW {name: g.type, wallet_count: total}]->(t)
WITH t, g
UNWIND range(0, size(g.rows) - 1) AS i
WITH t, g, i, g.rows[i] AS r
CREATE (s:SNet:SStatic {key: 'ww:' + g.type + ':' + r.status})
SET s.name = toString(r.n), s.outer = r.status, s.status = r.status,
    s.account_type = g.type, s.wallet_count = r.n,
    s.pin_x = -620.0, s.pin_y = g.y - (size(g.rows) - 1) * 20.0 + i * 40.0
CREATE (t)-[:SFLOW {name: '', wallet_count: r.n}]->(s);


// 3.4  (789) --txn_type--> (TXN_TYPE), and the half ring to its right.
//      The ring holds, biggest amount first from top to bottom:
//        * the top `ring_types` transaction types (service fees excluded)
//        * "More types (n)"          - the smaller types, one click away
//        * "Others (n service fees)" - every *-SERVICE_FEE type
//      It opens to the right, away from the rest of the drawing, so every
//      click fans out into free space.
//        inside  = distinct TXN_WITH_ACC that used the type(s)
//        outside = the type name, and the amount under it
MATCH (c:SNet {key: 'cust789'})
CALL {
  MATCH (r:SusRow) WHERE r.txn_type <> ''
  RETURN count(DISTINCT r.txn_type) AS type_count, sum(r.amount) AS total
}
CREATE (h:SNet:STypeHub {key: 'type_hub'})
SET h.name = toString(type_count), h.outer = 'TXN_TYPE', h.type_count = type_count, h.total = total,
    h.pin_x = $hub_x, h.pin_y = $hub_y
CREATE (c)-[:SFLOW {name: 'txn_type', amount: total}]->(h);

MATCH (h:SNet {key: 'type_hub'})
CALL {
  MATCH (r:SusRow) WHERE r.txn_type <> '' AND NOT r.txn_type ENDS WITH '-SERVICE_FEE'
  WITH r.txn_type AS ty, sum(r.amount) AS amt
  ORDER BY amt DESC, ty ASC
  RETURN collect(ty) AS ranked
}
CALL {
  MATCH (r:SusRow) WHERE r.txn_type ENDS WITH '-SERVICE_FEE'
  RETURN collect(DISTINCT r.txn_type) AS fee_types
}
WITH h,
     [ty IN ranked[0 .. $ring_types] | {key: 'type:' + ty, label: 'SType', types: [ty], outer: ty}] +
     CASE WHEN size(ranked) > $ring_types
          THEN [{key: 'type:__more', label: 'SMoreTypes', types: ranked[$ring_types ..],
                 outer: 'More types (' + toString(size(ranked) - $ring_types) + ')'}]
          ELSE [] END +
     CASE WHEN size(fee_types) > 0
          THEN [{key: 'type:__fees', label: 'SFeeGroup', types: fee_types,
                 outer: 'Others (' + toString(size(fee_types)) + ' service fees)'}]
          ELSE [] END AS items
WITH h, items, size(items) AS n, radians($ring_arc_deg) AS arc
WITH h, items, n, arc,
     CASE WHEN n > 1 AND $radial_spacing * (n - 1) / arc > $radii[0]
          THEN $radial_spacing * (n - 1) / arc ELSE $radii[0] END AS R
UNWIND range(0, n - 1) AS i
WITH h, items[i] AS t, R,
     CASE WHEN n > 1 THEN -arc / 2 + i * arc / (n - 1) ELSE 0.0 END AS a
CALL {
  WITH t
  MATCH (r:SusRow) WHERE r.txn_type IN t.types
  RETURN sum(r.amount) AS amt,
         sum(CASE WHEN r.txn_mode = 'CREDIT' THEN r.amount ELSE 0 END) AS cr,
         sum(CASE WHEN r.txn_mode = 'DEBIT'  THEN r.amount ELSE 0 END) AS dr,
         count(DISTINCT r.with_acc) AS with_wallets, count(DISTINCT r.wallet) AS suspected,
         sum(r.txn_count) AS txns
}
CALL apoc.create.node(['SNet', t.label], {key: t.key}) YIELD node AS n
SET n.name = toString(with_wallets), n.outer = t.outer, n.f_types = t.types,
    n.amount = amt, n.credit_amount = cr, n.debit_amount = dr,
    n.with_wallets = with_wallets, n.suspected_wallets = suspected, n.txn_count = txns,
    n.lvl = 1, n.ang = a, n.label_angle = a,
    n.pin_x = h.pin_x + R * cos(a), n.pin_y = h.pin_y + R * sin(a)
CREATE (h)-[:SFLOW {amount: amt, fmt: true}]->(n);


// 3.5  Every base node's `chain` is just its own key. Hidden nodes below
//      extend their parent's chain.
MATCH (n:SNet) SET n.chain = [n.key];


// 3.6  Click a group on the ring -> one node per type inside it:
//        "Others (service fees)" -> each service fee type (its total fee)
//        "More types"            -> each smaller transaction type
//      inside = distinct TXN_WITH_ACC, outside = type name + amount.
//      Each of these opens its wallets in turn (3.7).
MATCH (g:SNet) WHERE g:SFeeGroup OR g:SMoreTypes
CALL {
  WITH g
  MATCH (r:SusRow) WHERE r.txn_type IN g.f_types
  WITH r.txn_type AS ty, sum(r.amount) AS amt,
       sum(CASE WHEN r.txn_mode = 'CREDIT' THEN r.amount ELSE 0 END) AS cr,
       sum(CASE WHEN r.txn_mode = 'DEBIT'  THEN r.amount ELSE 0 END) AS dr,
       count(DISTINCT r.with_acc) AS with_wallets, count(DISTINCT r.wallet) AS suspected,
       sum(r.txn_count) AS txns
  ORDER BY amt DESC, ty ASC
  RETURN collect({ty: ty, amt: amt, cr: cr, dr: dr, with_wallets: with_wallets,
                  suspected: suspected, txns: txns}) AS kids
}
MATCH (h:SNet {key: 'type_hub'})
WITH g, h, kids, size(kids) AS n, $radii[g.lvl] AS R
UNWIND range(0, n - 1) AS i
WITH g, h, kids[i] AS t, R, g.ang + (i - (n - 1) / 2.0) * $radial_spacing / R AS a
WITH g, h, t, R, a, CASE WHEN g:SFeeGroup THEN 'fee:' ELSE 'type:' END + t.ty AS key
CALL apoc.create.node(['SNet', CASE WHEN g:SFeeGroup THEN 'SFeeType' ELSE 'SType' END], {key: key})
YIELD node AS f
SET f.name = toString(t.with_wallets), f.outer = t.ty, f.f_types = [t.ty],
    f.amount = t.amt, f.credit_amount = t.cr, f.debit_amount = t.dr,
    f.with_wallets = t.with_wallets, f.suspected_wallets = t.suspected, f.txn_count = t.txns,
    f.parent_key = g.key, f.chain = g.chain + [key],
    f.lvl = g.lvl + 1, f.ang = a, f.label_angle = a,
    f.pin_x = h.pin_x + R * cos(a), f.pin_y = h.pin_y + R * sin(a)
CREATE (g)-[:SFLOW {amount: t.amt, fmt: true}]->(f);


// 3.7  Click a transaction type (or a service fee type) -> its top
//      suspected wallets, plus "Others (n wallets)".
//        inside  = distinct TXN_WITH_ACC that wallet dealt with (in the type)
//        outside = SUSPECTED_WALLET, and the amount within the type
MATCH (t:SNet) WHERE t:SType OR t:SFeeType
CALL {
  WITH t
  MATCH (r:SusRow) WHERE r.txn_type IN t.f_types
  WITH r.wallet AS w, sum(r.amount) AS amt,
       sum(CASE WHEN r.txn_mode = 'CREDIT' THEN r.amount ELSE 0 END) AS cr,
       sum(CASE WHEN r.txn_mode = 'DEBIT'  THEN r.amount ELSE 0 END) AS dr,
       count(DISTINCT r.with_acc) AS cps, sum(r.txn_count) AS txns
  ORDER BY amt DESC, w ASC
  RETURN collect({w: w, amt: amt, cr: cr, dr: dr, cps: cps, txns: txns}) AS all
}
WITH t, all[0 .. $top_wallets] AS head, all[$top_wallets ..] AS tail
WITH t, head, tail,
     head + CASE WHEN size(tail) > 0
                 THEN [{w: '__others', amt: reduce(s = 0.0, x IN tail | s + x.amt),
                        cps: size(tail), wallets: [x IN tail | x.w]}]
                 ELSE [] END AS kids
MATCH (h:SNet {key: 'type_hub'})
WITH t, h, kids, size(kids) AS n, $radii[t.lvl] AS R
UNWIND range(0, n - 1) AS i
WITH t, h, kids[i] AS x, i, R, t.ang + (i - (n - 1) / 2.0) * $radial_spacing / R AS a
WITH t, h, x, i, a, R, 'sw:' + t.key + ':' + x.w AS key
CALL apoc.create.node(['SNet', CASE WHEN x.w = '__others' THEN 'SWalletOthers' ELSE 'SWallet' END], {key: key})
YIELD node AS n
SET n.name       = toString(x.cps),
    n.outer      = CASE WHEN x.w = '__others' THEN 'Others (' + toString(x.cps) + ' wallets)' ELSE x.w END,
    n.rank       = i + 1,
    n.wallet     = CASE WHEN x.w = '__others' THEN null ELSE x.w END,
    n.f_types    = t.f_types,
    n.f_wallet   = CASE WHEN x.w = '__others' THEN null ELSE x.w END,
    n.f_wallets  = x.wallets,
    n.amount     = x.amt,
    n.credit_amount = x.cr,
    n.debit_amount  = x.dr,
    n.with_wallets  = CASE WHEN x.w = '__others' THEN null ELSE x.cps END,
    n.txn_count  = x.txns,
    n.parent_key = t.key,
    n.chain      = t.chain + [key],
    n.lvl        = t.lvl + 1,
    n.ang        = a,
    n.label_angle = a,
    n.pin_x      = h.pin_x + R * cos(a),
    n.pin_y      = h.pin_y + R * sin(a)
CREATE (t)-[:SFLOW {amount: x.amt, fmt: true}]->(n);


// 3.8  Click a suspected wallet -> who it transacted with: one node per
//      (TXN_WITH_ACC, TXN_MODE), top `top_counterparties`, plus Others.
//        inside  = TXN_COUNT
//        outside = TXN_WITH_ACC, and "CREDIT · amount" / "DEBIT · amount"
//      The arrow follows the money: CREDIT points INTO the suspected
//      wallet, DEBIT points out of it.
MATCH (w:SWallet)
CALL {
  WITH w
  MATCH (r:SusRow {wallet: w.wallet}) WHERE r.txn_type IN w.f_types
  WITH r.with_acc AS cp, r.txn_mode AS mode, sum(r.amount) AS amt, sum(r.txn_count) AS txns
  ORDER BY amt DESC, cp ASC, mode ASC
  RETURN collect({cp: cp, mode: mode, amt: amt, txns: txns}) AS all
}
WITH w, all[0 .. $top_counterparties] AS head, all[$top_counterparties ..] AS tail
WITH w, head + CASE WHEN size(tail) > 0
                    THEN [{cp: '__others', mode: null, amt: reduce(s = 0.0, x IN tail | s + x.amt),
                           txns: size(tail)}]
                    ELSE [] END AS kids
MATCH (h:SNet {key: 'type_hub'})
WITH w, h, kids, size(kids) AS n, $radii[w.lvl] AS R
UNWIND range(0, n - 1) AS i
WITH w, h, kids[i] AS x, i, R, w.ang + (i - (n - 1) / 2.0) * $radial_spacing / R AS a
WITH w, h, x, i, a, R,
     CASE WHEN x.cp = '__others' THEN 'scp:' + w.key + ':__others'
          ELSE 'scp:' + w.key + ':' + x.mode + ':' + x.cp END AS key
CALL apoc.create.node(['SNet', CASE WHEN x.cp = '__others' THEN 'SCounterpartyOthers' ELSE 'SCounterparty' END], {key: key})
YIELD node AS n
SET n.name       = toString(x.txns),
    n.outer      = CASE WHEN x.cp = '__others' THEN 'Others (' + toString(x.txns) + ')' ELSE x.cp END,
    n.rank       = i + 1,
    n.txn_mode   = x.mode,
    n.f_types    = w.f_types,
    n.f_wallet   = w.wallet,
    n.f_with     = CASE WHEN x.cp = '__others' THEN null ELSE x.cp END,
    n.f_mode     = x.mode,
    n.amount     = x.amt,
    n.txn_count  = CASE WHEN x.cp = '__others' THEN null ELSE x.txns END,
    n.parent_key = w.key,
    n.chain      = w.chain + [key],
    n.lvl        = w.lvl + 1,
    n.ang        = a,
    n.label_angle = a,
    n.pin_x      = h.pin_x + R * cos(a),
    n.pin_y      = h.pin_y + R * sin(a)
WITH w, n, x
FOREACH (_ IN CASE WHEN x.mode = 'CREDIT' THEN [1] ELSE [] END |
  CREATE (n)-[:SFLOW {amount: x.amt, fmt: true, prefix: 'CREDIT '}]->(w))
FOREACH (_ IN CASE WHEN x.mode = 'CREDIT' THEN [] ELSE [1] END |
  CREATE (w)-[:SFLOW {amount: x.amt, fmt: true, prefix: CASE WHEN x.mode IS NULL THEN '' ELSE x.mode + ' ' END}]->(n));


// 3.9  Amounts, in short Bangladeshi notation:
//      1382920243.5 -> "138.29 Crore tk"; the exact figure stays on `amount`.
//      On the radial part (ring and everything a click opens) the amount is
//      written as the second line of the CHILD's label (`outer2`) and the
//      spoke itself carries no text. Elsewhere the amount is the
//      relationship caption.
MATCH (a:SNet)-[r:SFLOW]->(b:SNet) WHERE r.fmt
WITH a, b, r, coalesce(r.amount, 0.0) AS v,
     CASE WHEN b.label_angle IS NOT NULL AND (b.parent_key = a.key OR a.key = 'type_hub') THEN b
          WHEN a.label_angle IS NOT NULL AND a.parent_key = b.key THEN a
          ELSE null END AS child
WITH a, b, r, child,
     CASE WHEN r.prefix IS NULL OR r.prefix = '' THEN '' ELSE trim(r.prefix) + ' · ' END + CASE
       WHEN abs(v) >= 10000000 THEN toString(round(v / 10000000.0, 2)) + ' Crore tk'
       WHEN abs(v) >= 100000   THEN toString(round(v / 100000.0, 2))   + ' Lakh tk'
       WHEN abs(v) >= 1000     THEN toString(round(v / 1000.0, 2))     + ' Thousand tk'
       ELSE toString(round(v, 2)) + ' tk'
     END AS caption
SET r.name = CASE WHEN child IS NULL THEN caption ELSE '' END,
    r.amount_text = caption
FOREACH (c IN CASE WHEN child IS NULL THEN [] ELSE [child] END | SET c.outer2 = caption)
REMOVE r.fmt, r.prefix;


// 3.10 STYLE for the WHOLE graph - shape, colour and a plain-English
//      `role` for every node. Change a colour here and the legend (3.11)
//      follows.
//        Status (round):        SUSPENDED orange, ACTIVE green,
//                               DELETED light grey, PRELIMINARY yellow
//        Account (rounded box): Agent blue (Uddokta counts as Agent),
//                               Customer baby purple (the suspected wallets
//                               are customers too), Merchant rose, TR slate
//        Transaction type (hexagon, dark green, white text): TXN_TYPE,
//                               every type, More types, service fees
//        Counterparty (rounded box): CREDIT teal, DEBIT sand
//        Group of wallets (circle, sage) - 1872, 84930
//        Amount (diamond, apricot)       - 90 Cr
//        Others (dashed circle, pale)    - the rest of a list, grouped
MATCH (n:SNet)
WITH n,
  CASE
    WHEN n.status = 'SUSPENDED'                    THEN ['circle',  '#F4A66A', 'SUSPENDED wallets']
    WHEN n.status = 'ACTIVE'                       THEN ['circle',  '#8FCB9B', 'ACTIVE wallets']
    WHEN n.status = 'DELETED'                      THEN ['circle',  '#D9D9D9', 'DELETED wallets']
    WHEN n.status = 'PRELIMINARY_ACCOUNT'          THEN ['circle',  '#F5D76E', 'PRELIMINARY_ACCOUNT wallets']
    WHEN n.acct = 'Agent'                          THEN ['box',     '#8DB4E2',
                                                         CASE WHEN n.key = 'agent' THEN 'Agent account'
                                                              WHEN n.key = 'ww:Uddokta' THEN 'Uddokta (agent) wallets'
                                                              ELSE 'Agent wallets' END]
    WHEN n.acct = 'Customer'                       THEN ['box',     '#D8C8F0',
                                                         CASE WHEN n.key = 'customer' THEN 'Customer account'
                                                              WHEN n.key = 'cust789' THEN 'Suspected customer wallets'
                                                              ELSE 'Customer wallets' END]
    WHEN n.acct = 'Merchant'                       THEN ['box',     '#F0C6D2', 'Merchant wallets']
    WHEN n.acct = 'TR'                             THEN ['box',     '#C9D3DE', 'TR account']
    WHEN n.key = 'amount'                          THEN ['diamond', '#F5CFA0', 'Amount of money']
    WHEN n:STypeHub                                THEN ['hexagon', '#2F6F55', 'All transaction types']
    WHEN n:SType                                   THEN ['hexagon', '#2F6F55', 'Transaction type']
    WHEN n:SMoreTypes                              THEN ['hexagon', '#2F6F55', 'Smaller transaction types (grouped)']
    WHEN n:SFeeGroup                               THEN ['hexagon', '#2F6F55', 'Service fees (Others)']
    WHEN n:SFeeType                                THEN ['hexagon', '#2F6F55', 'Service fee type']
    WHEN n:SWallet                                 THEN ['box',     '#D8C8F0', 'Suspected wallet (customer)']
    WHEN n:SCounterparty AND n.txn_mode = 'CREDIT' THEN ['box',     '#A8DCD1', 'Counterparty - CREDIT (money in)']
    WHEN n:SCounterparty                           THEN ['box',     '#EED9B0', 'Counterparty - DEBIT (money out)']
    WHEN n:SWalletOthers                           THEN ['dashed',  '#EEF0F2', 'Other suspected wallets']
    WHEN n:SCounterpartyOthers                     THEN ['dashed',  '#EEF0F2', 'Other counterparties']
    ELSE                                                ['circle',  '#CFE3C8', 'Group of wallets']
  END AS st,
  CASE n.key WHEN 'w1872' THEN 6 WHEN 'agent1082' THEN 4 WHEN 'cust789' THEN 4
             WHEN 'with_wallets' THEN 4 WHEN 'type_hub' THEN 4 WHEN 'amount' THEN 3 ELSE 0 END AS boost
WITH n, st, boost,
     CASE WHEN size(n.name) * 2.5 + 4 > 9 THEN size(n.name) * 2.5 + 4 ELSE 9.0 END + boost AS radius
SET n.shape      = st[0],
    n.color      = st[1],
    n.role       = st[2],
    n.text_color = CASE WHEN st[1] = '#2F6F55' THEN '#FFFFFF' ELSE null END,
    n.click      = n.key,
    // `level` only keeps an OLD cached copy of the dashboard working (its
    // graph query drew nodes with level <= 5); the current one uses parent_key
    n.level      = CASE WHEN n.parent_key IS NULL THEN 1 ELSE 6 END,
    n.size       = round((radius / 4.0) ^ 2, 2);


// 3.11 The legend card: the same shapes and colours, with what they mean.
UNWIND [
  ['circle',  '#F4A66A', '340',   'SUSPENDED wallets'],
  ['circle',  '#8FCB9B', '441',   'ACTIVE wallets'],
  ['circle',  '#D9D9D9', '8',     'DELETED wallets'],
  ['circle',  '#F5D76E', '95',    'PRELIMINARY_ACCOUNT wallets'],
  ['box',     '#8DB4E2', 'Agent', 'Agent / Uddokta'],
  ['box',     '#D8C8F0', 'Cust.', 'Customer / suspected wallet'],
  ['box',     '#F0C6D2', '533',   'Merchant'],
  ['box',     '#C9D3DE', 'TR',    'TR account (from the notes)'],
  ['hexagon', '#2F6F55', '32',    'Transaction type / service fee'],
  ['circle',  '#CFE3C8', '1872',  'Group of wallets (count inside)'],
  ['diamond', '#F5CFA0', 'tk',    'Amount of money'],
  ['box',     '#A8DCD1', 'n',     'Counterparty - CREDIT (money in)'],
  ['box',     '#EED9B0', 'n',     'Counterparty - DEBIT (money out)'],
  ['dashed',  '#EEF0F2', 'n',     'Others - the rest, grouped']
] AS e
WITH collect(e) AS rows
UNWIND range(0, size(rows) - 1) AS i
WITH i, rows[i] AS e
CREATE (l:SLegend {key: 'legend:' + toString(i)})
SET l.shape = e[0], l.color = e[1], l.name = e[2], l.outer = e[3], l.rank = i,
    l.text_color = CASE WHEN e[1] = '#2F6F55' THEN '#FFFFFF' ELSE null END,
    l.pin_x = 0.0, l.pin_y = toFloat(i * 28),
    l.size = round(((CASE WHEN size(e[2]) * 2.5 + 4 > 9 THEN size(e[2]) * 2.5 + 4 ELSE 9.0 END) / 4.0) ^ 2, 2);


// 3.12 Report - the base graph, then what waits behind clicks.
MATCH (n:SNet) WHERE n.parent_key IS NULL
RETURN [l IN labels(n) WHERE l <> 'SNet'][0] AS kind, n.name AS inside, n.outer AS outside, n.role AS role
ORDER BY kind, n.pin_y;
MATCH (n:SNet) WHERE n.parent_key IS NOT NULL
RETURN [l IN labels(n) WHERE l <> 'SNet'][0] AS on_click, count(*) AS nodes
ORDER BY on_click;
