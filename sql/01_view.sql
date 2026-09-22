-- =====================================================================
-- KGN4j : the only SQL file you need.
--
-- Creates two views over your existing table. Changes nothing about the
-- table itself. Safe to re-run.
--
-- Source : database `neo4j`, table `public.neo4j`, 6.7M rows
-- Run in : pgAdmin Query Tool, connected to the `neo4j` database
--
-- DESIGN NOTE - why this is so plain:
-- An earlier version parsed every date with a PL/pgSQL function that
-- tried eleven formats inside an exception block. That is fine on a
-- small table and pathological on millions of rows, because each failed
-- attempt opens a subtransaction. Here nothing is parsed: dates are
-- passed through as text (nothing in the graph sorts or filters by
-- date), and the two numeric columns are cast behind a regex guard
-- rather than an exception handler. No function calls, no
-- subtransactions, one pass over the table.
-- =====================================================================

DROP VIEW IF EXISTS public.v_account_summary;
DROP VIEW IF EXISTS public.v_txn_for_graph;

CREATE VIEW public.v_txn_for_graph AS
SELECT
    -- Stable unique id per row. NOTE: do NOT use UNQ_ID - in this export
    -- it is the constant 'NGD_PATHAO_PAY_V4' on all 6.7M rows, i.e. it
    -- names the extract, not the transaction. This composite was verified
    -- unique over a 1.5M row sample.
    btrim("STATEMENT_FOR_ACC"::text) || '|' ||
    coalesce(btrim("TXN_ID"::text), '') || '|' ||
    coalesce(btrim("SerialNo"::text), '') || '|' ||
    CASE WHEN upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'D%' THEN 'D' ELSE 'C' END
                                                   AS row_key,

    btrim("UNQ_ID"::text)                          AS unq_id,

    -- dates pass through as text, exactly as they are stored
    btrim("FROM_DATE"::text)                       AS from_date,
    btrim("TO_DATE"::text)                         AS to_date,
    btrim("TXN_DATE_TIME"::text)                   AS txn_date_time,

    -- integer behind a regex guard
    CASE WHEN btrim("SerialNo"::text) ~ '^[0-9]+$'
         THEN btrim("SerialNo"::text)::bigint END  AS serialno,

    btrim("TXN_ID"::text)                          AS txn_id,
    btrim("TXN_TYPE"::text)                        AS txn_type,
    btrim("ACCOUNT_TYPE"::text)                    AS account_type,
    btrim("STATEMENT_FOR_ACC"::text)               AS statement_for_acc,
    NULLIF(btrim("TXN_WITH_ACC"::text), '')        AS txn_with_acc,
    btrim("CHANNEL"::text)                         AS channel,
    btrim("REFERENCE"::text)                       AS reference,

    -- DEBIT -> D, CREDIT -> C (also handles D/C, Dr/Cr, debit/credit)
    CASE
        WHEN upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'D%' THEN 'D'
        WHEN upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'C%' THEN 'C'
    END                                            AS txn_type_d_c,

    btrim("STATUS"::text)                          AS status,

    -- amounts behind a regex guard; anything unparseable becomes 0
    CASE WHEN btrim("TXN_AMT"::text) ~ '^-?[0-9]+(\.[0-9]+)?$'
         THEN btrim("TXN_AMT"::text)::numeric
         ELSE 0 END                                AS txn_amt,
    CASE WHEN btrim("AVAILABLE_BLC_AFTER_TXN"::text) ~ '^-?[0-9]+(\.[0-9]+)?$'
         THEN btrim("AVAILABLE_BLC_AFTER_TXN"::text)::numeric
         ELSE 0 END                                AS available_blc_after_txn,

    btrim("TXN_WITH_INFO"::text)                   AS txn_with_info,

    -- Direction of the money. This is the one piece of real logic here:
    -- a row on the sender's statement is marked D, the mirror row on the
    -- receiver's statement is marked C, and this makes both point the
    -- same way so the graph is correctly directed.
    CASE WHEN upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'D%'
         THEN btrim("STATEMENT_FOR_ACC"::text)
         ELSE NULLIF(btrim("TXN_WITH_ACC"::text), '') END      AS from_acc,
    CASE WHEN upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'D%'
         THEN NULLIF(btrim("TXN_WITH_ACC"::text), '')
         ELSE btrim("STATEMENT_FOR_ACC"::text) END             AS to_acc

FROM public.neo4j
WHERE (upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'D%'
    OR upper(btrim("TXN_TYPE_D_C"::text)) LIKE 'C%')
  AND btrim("STATEMENT_FOR_ACC"::text) <> ''
  AND coalesce(btrim("TXN_WITH_ACC"::text), '') <> '';


CREATE VIEW public.v_account_summary AS
SELECT
    statement_for_acc,
    max(account_type)                                            AS account_type,
    count(*)                                                     AS txn_count,
    coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c = 'D'), 0)  AS total_debit,
    coalesce(sum(txn_amt) FILTER (WHERE txn_type_d_c = 'C'), 0)  AS total_credit
FROM public.v_txn_for_graph
GROUP BY statement_for_acc;


-- =====================================================================
-- CHECK: this must show ~6,746,792. If it shows 0, stop and tell me.
-- =====================================================================
SELECT (SELECT count(*) FROM public.neo4j)           AS base_table_rows,
       (SELECT count(*) FROM public.v_txn_for_graph) AS view_rows;
