// CARD - "By TXN_TYPE" (report type: Table)
// Every transaction type in the sheet, including the ones the graph
// rolls into "Others". Amounts in tk; CRORE is the same figure / 1e7.
MATCH (r:SusRow)
WITH r.txn_type AS TXN_TYPE,
     sum(r.amount) AS amt,
     sum(CASE WHEN r.txn_mode = 'CREDIT' THEN r.amount ELSE 0 END) AS cr,
     sum(CASE WHEN r.txn_mode = 'DEBIT'  THEN r.amount ELSE 0 END) AS dr,
     count(DISTINCT r.with_acc) AS with_wallets,
     count(DISTINCT r.wallet)   AS suspected,
     sum(r.txn_count)           AS txns
RETURN TXN_TYPE,
       with_wallets         AS TXN_WITH_WALLETS,
       suspected            AS SUSPECTED_WALLETS,
       txns                 AS TXN_COUNT,
       round(amt, 2)        AS TXN_AMOUNT,
       round(amt / 1e7, 2)  AS CRORE,
       round(cr, 2)         AS CREDIT,
       round(dr, 2)         AS DEBIT
ORDER BY TXN_AMOUNT DESC
