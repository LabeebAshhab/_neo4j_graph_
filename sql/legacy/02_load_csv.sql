-- =====================================================================
-- KGN4j : load the CSV
-- =====================================================================
-- OPTION A (what you asked for) - use the pgAdmin UI:
--   1. Run sql/01_schema.sql first.
--   2. In the pgAdmin browser tree:  kgn4j > Schemas > stmt > Tables
--      > txn_stage  ->  right click  ->  Import/Export Data...
--   3. Import tab:
--        Filename : C:\Nagad.work\KGN4j\data\sample_transactions.csv
--        Format   : csv
--        Encoding : UTF8
--        Header   : Yes
--        Delimiter: ,
--      Columns tab: leave all 17 columns selected, in file order.
--   4. Click OK. Then run STEP 2 below.
--
-- OPTION B - if you prefer SQL, run this from the pgAdmin query tool
-- while connected as a superuser ON THE SERVER MACHINE:
--
--   COPY stmt.txn_stage
--   FROM 'C:\Nagad.work\KGN4j\data\sample_transactions.csv'
--   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
--
-- (COPY reads the file on the PostgreSQL server. If pgAdmin runs on a
--  different machine than the server, use Option A.)
-- =====================================================================


-- =====================================================================
-- STEP 2 : stage  ->  typed table
-- Always safe to re-run; it rebuilds stmt.transactions from scratch.
-- =====================================================================
TRUNCATE stmt.transactions;

INSERT INTO stmt.transactions (
    unq_id, from_date, to_date, serialno, txn_date_time, txn_id, txn_type,
    account_type, statement_for_acc, txn_with_acc, channel, reference,
    txn_type_d_c, status, txn_amt, available_blc_after_txn, txn_with_info,
    row_key
)
SELECT
    btrim(s.unq_id),
    stmt.safe_ts(s.from_date)::DATE,
    stmt.safe_ts(s.to_date)::DATE,
    NULLIF(regexp_replace(coalesce(s.serialno,''), '[^0-9]', '', 'g'), '')::INTEGER,
    stmt.safe_ts(s.txn_date_time),
    btrim(s.txn_id),
    btrim(s.txn_type),
    btrim(s.account_type),
    btrim(s.statement_for_acc),
    NULLIF(btrim(s.txn_with_acc), ''),
    btrim(s.channel),
    btrim(s.reference),
    -- normalise anything like 'debit', 'Dr', 'D' to 'D'
    CASE
        WHEN upper(btrim(coalesce(s.txn_type_d_c,''))) LIKE 'D%' THEN 'D'
        WHEN upper(btrim(coalesce(s.txn_type_d_c,''))) LIKE 'C%' THEN 'C'
        ELSE NULL
    END,
    btrim(s.status),
    stmt.safe_num(s.txn_amt),
    stmt.safe_num(s.available_blc_after_txn),
    btrim(s.txn_with_info),
    -- row_key: unq_id when present, otherwise a deterministic composite
    coalesce(
        NULLIF(btrim(s.unq_id), ''),
        btrim(coalesce(s.statement_for_acc,'')) || '|' ||
        btrim(coalesce(s.txn_id,''))            || '|' ||
        btrim(coalesce(s.serialno,''))          || '|' ||
        btrim(coalesce(s.txn_date_time,''))
    )
FROM stmt.txn_stage s
WHERE btrim(coalesce(s.statement_for_acc,'')) <> ''
ON CONFLICT (row_key) DO NOTHING;


-- =====================================================================
-- STEP 3 : sanity checks - look at these before moving to Neo4j
-- =====================================================================
SELECT count(*) AS rows_loaded FROM stmt.transactions;

SELECT statement_for_acc,
       count(*)                                                   AS txns,
       count(*) FILTER (WHERE txn_type_d_c = 'D')                  AS debits,
       count(*) FILTER (WHERE txn_type_d_c = 'C')                  AS credits,
       sum(txn_amt) FILTER (WHERE txn_type_d_c = 'D')              AS total_debit,
       sum(txn_amt) FILTER (WHERE txn_type_d_c = 'C')              AS total_credit
FROM stmt.transactions
GROUP BY statement_for_acc
ORDER BY statement_for_acc;

-- rows that failed to parse - should be empty
SELECT * FROM stmt.transactions
WHERE txn_date_time IS NULL OR txn_type_d_c IS NULL;
