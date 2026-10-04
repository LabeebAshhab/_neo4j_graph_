// CARD - "Sheet rows" (report type: Table)
// The source rows behind the node clicked in the graph.
//   a TXN_TYPE node (P2P, CASH OUT, ...) -> that type
//   Others (types)                       -> the types rolled into it
//   a suspected wallet                   -> that wallet, within the type
//   Others (wallets)                     -> those wallets, within the type
//   a TXN_WITH_ACC node                  -> that wallet + counterparty + mode
//   any other node                       -> every row (top by amount)
// Unknown / stale focus falls back to every row.
WITH coalesce($neodash_sus_focus, '') AS fk
OPTIONAL MATCH (f:SNet {key: fk})
WITH f.f_types AS types, f.f_wallet AS wallet, f.f_wallets AS wallets,
     f.f_with AS with_acc, f.f_mode AS mode
MATCH (r:SusRow)
WHERE (types    IS NULL OR r.txn_type IN types)
  AND (wallet   IS NULL OR r.wallet = wallet)
  AND (wallets  IS NULL OR r.wallet IN wallets)
  AND (with_acc IS NULL OR r.with_acc = with_acc)
  AND (mode     IS NULL OR r.txn_mode = mode)
RETURN r.wallet    AS SUSPECTED_WALLET,
       r.with_acc  AS TXN_WITH_ACC,
       r.txn_type  AS TXN_TYPE,
       r.txn_mode  AS TXN_MODE,
       r.txn_count AS TXN_COUNT,
       r.amount    AS TXN_AMOUNT
ORDER BY TXN_AMOUNT DESC
LIMIT 2000
