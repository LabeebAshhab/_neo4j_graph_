// CARD - "Selected" (report type: Table, single row)
// What was clicked, and what the rows table is filtered to.
WITH coalesce($neodash_sus_focus, '') AS fk
OPTIONAL MATCH (f:SNet {key: fk})
WITH f, [x IN [
       CASE WHEN f.f_types   IS NOT NULL THEN 'TXN_TYPE IN ' + reduce(s = '', t IN f.f_types | CASE WHEN s = '' THEN t ELSE s + ', ' + t END) END,
       CASE WHEN f.f_wallet  IS NOT NULL THEN 'SUSPECTED_WALLET = ' + f.f_wallet END,
       CASE WHEN f.f_wallets IS NOT NULL THEN 'SUSPECTED_WALLET IN (' + toString(size(f.f_wallets)) + ' wallets)' END,
       CASE WHEN f.f_with    IS NOT NULL THEN 'TXN_WITH_ACC = ' + f.f_with END,
       CASE WHEN f.f_mode    IS NOT NULL THEN 'TXN_MODE = ' + f.f_mode END
     ] WHERE x IS NOT NULL] AS filters
RETURN coalesce(f.name, '-')  AS INSIDE,
       coalesce(f.outer, '')  AS OUTSIDE,
       CASE WHEN size(filters) = 0 THEN 'all rows'
            ELSE reduce(s = '', x IN filters | CASE WHEN s = '' THEN x ELSE s + '  AND  ' + x END)
       END AS ROWS_TABLE_FILTER,
       CASE WHEN f.amount IS NULL THEN coalesce(f.total, f.data_total) ELSE f.amount END AS AMOUNT
