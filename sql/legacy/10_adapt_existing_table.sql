-- =====================================================================
-- KGN4j : adapt an EXISTING imported table
--
-- Use this INSTEAD OF sql/01_schema.sql + 02 + 03 when you have already
-- imported the CSV into your own table with pgAdmin.
--
-- Defaults match what you described:
--     database : neo4j
--     schema   : public
--     table    : neo4j
--
-- Run it in the pgAdmin Query Tool **connected to the `neo4j` database**.
-- It creates two views that Neo4j reads, and changes nothing about your
-- table. Safe to re-run.
--
-- Column names are resolved CASE-INSENSITIVELY, so it works whether
-- pgAdmin created  unq_id  or  "UNQ_ID"  or  "SerialNo".
-- Column types do not matter either - every value is read as text and
-- parsed here, so a table of all-TEXT columns works exactly the same as
-- a fully typed one.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CONFIGURE: if your table lives elsewhere, change the two literals in
-- the DECLARE block of section 2 below (v_schema / v_table), and the
-- table name in the row-count check in section 3.
-- (psql's \set is not available in the pgAdmin Query Tool, so the
--  values are declared inline rather than as variables.)
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 1. Tolerant parsers (created in public, harmless if they exist)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.kgn4j_safe_ts(p TEXT)
RETURNS TIMESTAMP LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    f TEXT;
    formats TEXT[] := ARRAY[
        'YYYY-MM-DD HH24:MI:SS','YYYY-MM-DD"T"HH24:MI:SS',
        'DD/MM/YYYY HH24:MI:SS','MM/DD/YYYY HH24:MI:SS',
        'DD-MON-YYYY HH24:MI:SS','DD-MM-YYYY HH24:MI:SS',
        'YYYY/MM/DD HH24:MI:SS','DD-MON-YY HH12:MI:SS AM',
        'YYYY-MM-DD','DD/MM/YYYY','MM/DD/YYYY','DD-MON-YYYY'
    ];
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN NULL; END IF;
    FOREACH f IN ARRAY formats LOOP
        BEGIN RETURN to_timestamp(btrim(p), f); EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.kgn4j_safe_num(p TEXT)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE cleaned TEXT;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN 0; END IF;
    cleaned := regexp_replace(btrim(p), '[^0-9.\-]', '', 'g');
    IF cleaned IN ('', '-', '.') THEN RETURN 0; END IF;
    RETURN cleaned::NUMERIC;
EXCEPTION WHEN OTHERS THEN RETURN 0;
END $$;


-- ---------------------------------------------------------------------
-- 2. Build the two views by matching your column names case-insensitively
-- ---------------------------------------------------------------------
DO $build$
DECLARE
    v_schema TEXT := 'public';   -- <-- your schema
    v_table  TEXT := 'neo4j';    -- <-- your table
    wanted   TEXT[] := ARRAY[
        'unq_id','from_date','to_date','serialno','txn_date_time','txn_id',
        'txn_type','account_type','statement_for_acc','txn_with_acc','channel',
        'reference','txn_type_d_c','status','txn_amt',
        'available_blc_after_txn','txn_with_info'
    ];
    w        TEXT;
    actual   TEXT;
    missing  TEXT[] := '{}';
    col      JSONB  := '{}'::jsonb;
    sql      TEXT;
BEGIN
    IF to_regclass(format('%I.%I', v_schema, v_table)) IS NULL THEN
        RAISE EXCEPTION 'Table %.% was not found. Edit src_schema / src_table at the top of this file.', v_schema, v_table;
    END IF;

    -- resolve each wanted column to its real spelling
    FOREACH w IN ARRAY wanted LOOP
        SELECT c.column_name INTO actual
        FROM information_schema.columns c
        WHERE c.table_schema = v_schema
          AND c.table_name   = v_table
          AND lower(replace(c.column_name, ' ', '')) = w
        LIMIT 1;

        IF actual IS NULL THEN
            missing := missing || w;
        ELSE
            col := col || jsonb_build_object(w, actual);
        END IF;
    END LOOP;

    IF array_length(missing, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'These columns were not found in %.%: %. Found: %',
            v_schema, v_table, array_to_string(missing, ', '),
            (SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
             FROM information_schema.columns
             WHERE table_schema = v_schema AND table_name = v_table);
    END IF;

    -- ---- main view -------------------------------------------------
    sql := format($f$
        CREATE OR REPLACE VIEW public.v_txn_for_graph AS
        WITH base AS (
            SELECT
                btrim(%1$I::text)  AS unq_id,
                btrim(%2$I::text)  AS from_date_raw,
                btrim(%3$I::text)  AS to_date_raw,
                btrim(%4$I::text)  AS serialno_raw,
                btrim(%5$I::text)  AS txn_date_time_raw,
                btrim(%6$I::text)  AS txn_id,
                btrim(%7$I::text)  AS txn_type,
                btrim(%8$I::text)  AS account_type,
                btrim(%9$I::text)  AS statement_for_acc,
                NULLIF(btrim(%10$I::text), '') AS txn_with_acc,
                btrim(%11$I::text) AS channel,
                btrim(%12$I::text) AS reference,
                CASE
                    WHEN upper(btrim(coalesce(%13$I::text,''))) LIKE 'D%%' THEN 'D'
                    WHEN upper(btrim(coalesce(%13$I::text,''))) LIKE 'C%%' THEN 'C'
                    ELSE NULL
                END AS txn_type_d_c,
                btrim(%14$I::text) AS status,
                public.kgn4j_safe_num(%15$I::text) AS txn_amt,
                public.kgn4j_safe_num(%16$I::text) AS available_blc_after_txn,
                btrim(%17$I::text) AS txn_with_info
            FROM %18$I.%19$I
        )
        SELECT
            coalesce(NULLIF(unq_id, ''),
                     statement_for_acc || '|' || coalesce(txn_id,'') || '|' ||
                     coalesce(serialno_raw,'') || '|' || coalesce(txn_date_time_raw,'')
            ) AS row_key,
            unq_id,
            public.kgn4j_safe_ts(from_date_raw)::date AS from_date,
            public.kgn4j_safe_ts(to_date_raw)::date   AS to_date,
            NULLIF(regexp_replace(coalesce(serialno_raw,''), '[^0-9]', '', 'g'), '')::int AS serialno,
            public.kgn4j_safe_ts(txn_date_time_raw)   AS txn_date_time,
            txn_id, txn_type, account_type, statement_for_acc, txn_with_acc,
            channel, reference, txn_type_d_c, status, txn_amt,
            available_blc_after_txn, txn_with_info,
            to_char(public.kgn4j_safe_ts(txn_date_time_raw), 'YYYY-MM-DD"T"HH24:MI:SS') AS txn_dt_iso,
            to_char(public.kgn4j_safe_ts(from_date_raw),     'YYYY-MM-DD')              AS from_date_iso,
            to_char(public.kgn4j_safe_ts(to_date_raw),       'YYYY-MM-DD')              AS to_date_iso,
            CASE WHEN txn_type_d_c = 'D' THEN statement_for_acc ELSE txn_with_acc      END AS from_acc,
            CASE WHEN txn_type_d_c = 'D' THEN txn_with_acc      ELSE statement_for_acc END AS to_acc
        FROM base
        WHERE txn_type_d_c IS NOT NULL
          AND coalesce(statement_for_acc,'') <> ''
          AND coalesce(txn_with_acc,'') <> ''
    $f$,
        col->>'unq_id', col->>'from_date', col->>'to_date', col->>'serialno',
        col->>'txn_date_time', col->>'txn_id', col->>'txn_type', col->>'account_type',
        col->>'statement_for_acc', col->>'txn_with_acc', col->>'channel',
        col->>'reference', col->>'txn_type_d_c', col->>'status', col->>'txn_amt',
        col->>'available_blc_after_txn', col->>'txn_with_info',
        v_schema, v_table);
    EXECUTE sql;

    -- ---- summary view ----------------------------------------------
    EXECUTE $s$
        CREATE OR REPLACE VIEW public.v_account_summary AS
        SELECT statement_for_acc,
               max(account_type)                                          AS account_type,
               count(*)                                                   AS txn_count,
               coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c='D'), 0)  AS total_debit,
               coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c='C'), 0)  AS total_credit
        FROM public.v_txn_for_graph
        GROUP BY statement_for_acc
    $s$;

    RAISE NOTICE 'Views public.v_txn_for_graph and public.v_account_summary created over %.%', v_schema, v_table;
END
$build$;


-- ---------------------------------------------------------------------
-- 3. Sanity checks - look at all three before moving to Neo4j
-- ---------------------------------------------------------------------

-- how many rows survived, and how many were dropped by the filters
SELECT
  (SELECT count(*) FROM public.v_txn_for_graph) AS rows_for_graph,
  (SELECT count(*) FROM public.neo4j)           AS rows_in_source;

-- per-account breakdown
SELECT * FROM public.v_account_summary ORDER BY statement_for_acc;

-- first few graph rows: check from_acc / to_acc point the right way
SELECT row_key, txn_date_time, txn_id, txn_type, txn_type_d_c,
       statement_for_acc, txn_with_acc, from_acc, to_acc, txn_amt
FROM public.v_txn_for_graph
ORDER BY statement_for_acc, txn_date_time
LIMIT 20;
