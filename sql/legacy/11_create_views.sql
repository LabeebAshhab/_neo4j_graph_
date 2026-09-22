-- =====================================================================
-- KGN4j : create the two views Neo4j reads
--
-- Plain version - no dynamic SQL. Column names are written out exactly
-- as they exist in your table, which pgAdmin created quoted and
-- mixed-case:  "UNQ_ID", "SerialNo", "TXN_AMT", ...
-- In PostgreSQL a quoted identifier is case-sensitive, so the quotes
-- and the capitalisation below are both required.
--
-- Source:  database `neo4j`, table `public.neo4j`
--
-- RUN THIS IN: pgAdmin Query Tool, connected to the `neo4j` database.
-- Safe to re-run. Changes nothing about your table.
--
-- Use this INSTEAD OF sql/10_adapt_existing_table.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tolerant parsers.
--    Statement exports carry inconsistent date formats and amounts with
--    commas or currency symbols, so values are read as text and parsed
--    here. A bad value yields NULL or 0 instead of failing the query.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.kgn4j_safe_ts(p TEXT)
RETURNS TIMESTAMP LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
    f TEXT;
    formats TEXT[] := ARRAY[
        'YYYY-MM-DD HH24:MI:SS', 'YYYY-MM-DD"T"HH24:MI:SS',
        'DD/MM/YYYY HH24:MI:SS', 'MM/DD/YYYY HH24:MI:SS',
        'DD-MON-YYYY HH24:MI:SS', 'DD-MM-YYYY HH24:MI:SS',
        'YYYY/MM/DD HH24:MI:SS',
        'YYYY-MM-DD', 'DD/MM/YYYY', 'MM/DD/YYYY', 'DD-MON-YYYY'
    ];
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN NULL; END IF;
    FOREACH f IN ARRAY formats LOOP
        BEGIN
            RETURN to_timestamp(btrim(p), f);
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END LOOP;
    RETURN NULL;
END $fn$;

CREATE OR REPLACE FUNCTION public.kgn4j_safe_num(p TEXT)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
    cleaned TEXT;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN 0; END IF;
    cleaned := regexp_replace(btrim(p), '[^0-9.\-]', '', 'g');
    IF cleaned IN ('', '-', '.') THEN RETURN 0; END IF;
    RETURN cleaned::NUMERIC;
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END $fn$;


-- ---------------------------------------------------------------------
-- 2. The main view.
--    `from_acc` / `to_acc` are derived from TXN_TYPE_D_C so that money
--    always flows from -> to, whichever side's statement a row is on.
--    That is what makes the graph directed and correct.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_account_summary;
DROP VIEW IF EXISTS public.v_txn_for_graph;

CREATE VIEW public.v_txn_for_graph AS
WITH base AS (
    SELECT
        btrim("UNQ_ID"::text)             AS unq_id,
        btrim("FROM_DATE"::text)          AS from_date_raw,
        btrim("TO_DATE"::text)            AS to_date_raw,
        btrim("SerialNo"::text)           AS serialno_raw,
        btrim("TXN_DATE_TIME"::text)      AS txn_date_time_raw,
        btrim("TXN_ID"::text)             AS txn_id,
        btrim("TXN_TYPE"::text)           AS txn_type,
        btrim("ACCOUNT_TYPE"::text)       AS account_type,
        btrim("STATEMENT_FOR_ACC"::text)  AS statement_for_acc,
        NULLIF(btrim("TXN_WITH_ACC"::text), '') AS txn_with_acc,
        btrim("CHANNEL"::text)            AS channel,
        btrim("REFERENCE"::text)          AS reference,
        CASE
            WHEN upper(btrim(coalesce("TXN_TYPE_D_C"::text, ''))) LIKE 'D%' THEN 'D'
            WHEN upper(btrim(coalesce("TXN_TYPE_D_C"::text, ''))) LIKE 'C%' THEN 'C'
            ELSE NULL
        END                               AS txn_type_d_c,
        btrim("STATUS"::text)             AS status,
        public.kgn4j_safe_num("TXN_AMT"::text)                 AS txn_amt,
        public.kgn4j_safe_num("AVAILABLE_BLC_AFTER_TXN"::text) AS available_blc_after_txn,
        btrim("TXN_WITH_INFO"::text)      AS txn_with_info
    FROM public.neo4j
)
SELECT
    -- stable unique id per row; Neo4j MERGEs transactions on this
    coalesce(
        NULLIF(unq_id, ''),
        statement_for_acc || '|' || coalesce(txn_id, '') || '|' ||
        coalesce(serialno_raw, '') || '|' || coalesce(txn_date_time_raw, '')
    )                                                   AS row_key,
    unq_id,
    public.kgn4j_safe_ts(from_date_raw)::date           AS from_date,
    public.kgn4j_safe_ts(to_date_raw)::date             AS to_date,
    NULLIF(regexp_replace(coalesce(serialno_raw, ''), '[^0-9]', '', 'g'), '')::int AS serialno,
    public.kgn4j_safe_ts(txn_date_time_raw)             AS txn_date_time,
    txn_id,
    txn_type,
    account_type,
    statement_for_acc,
    txn_with_acc,
    channel,
    reference,
    txn_type_d_c,
    status,
    txn_amt,
    available_blc_after_txn,
    txn_with_info,
    -- ISO text copies: Cypher builds its own temporal values from these,
    -- which avoids any driver-specific date handling
    to_char(public.kgn4j_safe_ts(txn_date_time_raw), 'YYYY-MM-DD"T"HH24:MI:SS') AS txn_dt_iso,
    to_char(public.kgn4j_safe_ts(from_date_raw),     'YYYY-MM-DD')              AS from_date_iso,
    to_char(public.kgn4j_safe_ts(to_date_raw),       'YYYY-MM-DD')              AS to_date_iso,
    -- direction of the money
    CASE WHEN txn_type_d_c = 'D' THEN statement_for_acc ELSE txn_with_acc      END AS from_acc,
    CASE WHEN txn_type_d_c = 'D' THEN txn_with_acc      ELSE statement_for_acc END AS to_acc
FROM base
WHERE txn_type_d_c IS NOT NULL
  AND coalesce(statement_for_acc, '') <> ''
  AND coalesce(txn_with_acc, '') <> '';


-- ---------------------------------------------------------------------
-- 3. Per-account summary
-- ---------------------------------------------------------------------
CREATE VIEW public.v_account_summary AS
SELECT
    statement_for_acc,
    max(account_type)                                             AS account_type,
    count(*)                                                      AS txn_count,
    coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c = 'D'), 0)   AS total_debit,
    coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c = 'C'), 0)   AS total_credit
FROM public.v_txn_for_graph
GROUP BY statement_for_acc;


-- ---------------------------------------------------------------------
-- 4. Checks - read all four before exporting
-- ---------------------------------------------------------------------

-- 4a. the views now exist
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'v_%'
ORDER BY table_name;

-- 4b. how many rows made it, and how many the filters dropped
SELECT
    (SELECT count(*) FROM public.neo4j)           AS rows_in_source,
    (SELECT count(*) FROM public.v_txn_for_graph) AS rows_for_graph;

-- 4c. why rows were dropped, if any were
SELECT
    count(*) FILTER (WHERE upper(btrim(coalesce("TXN_TYPE_D_C"::text,''))) NOT LIKE 'D%'
                       AND upper(btrim(coalesce("TXN_TYPE_D_C"::text,''))) NOT LIKE 'C%')
        AS dropped_bad_debit_credit_flag,
    count(*) FILTER (WHERE coalesce(btrim("TXN_WITH_ACC"::text), '') = '')
        AS dropped_no_counterparty,
    count(*) FILTER (WHERE coalesce(btrim("STATEMENT_FOR_ACC"::text), '') = '')
        AS dropped_no_statement_account,
    count(*) FILTER (WHERE public.kgn4j_safe_ts(btrim("TXN_DATE_TIME"::text)) IS NULL)
        AS unparsed_datetime
FROM public.neo4j;

-- 4d. per-account totals, and a look at the real rows
SELECT * FROM public.v_account_summary ORDER BY statement_for_acc;

SELECT row_key, txn_date_time, txn_id, txn_type, txn_type_d_c,
       statement_for_acc, txn_with_acc, from_acc, to_acc, txn_amt
FROM public.v_txn_for_graph
ORDER BY statement_for_acc, txn_date_time
LIMIT 20;
