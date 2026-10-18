-- =====================================================================
-- KGN4j - Layered Trail : the `layered` table in PostgreSQL
--
-- Run in pgAdmin's Query Tool, connected to database `neo4j`.
-- Pick ONE of A or B, then import the CSV (C).
--
-- The columns are in the same order as the CSV, so pgAdmin's
-- Import/Export can load it directly. Every column is text except
-- APPROVAL_DATETIME, so nothing in the file can make the import fail:
--   * account numbers stay as written (a text column never drops a
--     leading 0; numbers like 1912673646 that lost it before export are
--     fixed by scripts/load_layered_from_pg.py)
--   * TXN_WITH can be a non-number, e.g. "VISA DEBIT CARD"
--   * amounts like "49,995.00" or " 800.00 " import as written; the
--     loader reads them as numbers
--   * LAYERED_MONEY may be missing in older files (it stays empty)
-- =====================================================================


-- A. You ALREADY have the `layered` table (13 columns, from newtest.csv):
--    add the new last column. Safe to run more than once; nothing else
--    changes and no rows are lost.
ALTER TABLE public.layered ADD COLUMN IF NOT EXISTS layered_money varchar(50);


-- B. NEW laptop, no table yet: create it with all 14 columns.
CREATE TABLE IF NOT EXISTS public.layered (
    txn_sl_tag        varchar(50),
    approval_datetime timestamp,
    txn_id            varchar(50),
    txn_type          varchar(100),
    txn_with          varchar(100),
    txn_with_info     text,
    channel           varchar(50),
    status            varchar(50),
    txn_type_d_c      varchar(20),
    txn_amt           varchar(50),
    post_blc          varchar(50),
    layer             varchar(50),
    txn_from          varchar(50),
    layered_money     varchar(50)
);


-- C. Load the CSV.
--    The new file holds the whole trail again (layers 1-6), so empty the
--    table first - otherwise the old rows (with leading 0) and the new
--    ones (without) would both be there, every transfer twice.
TRUNCATE public.layered;
--    Then in pgAdmin: right click public.layered -> Import/Export Data...
--      Import, Filename = the CSV, Format csv, Header ON, Delimiter ,
--      Columns tab: all 14, in file order
--    (An older 13-column file such as newtest.csv also loads: untick
--     layered_money in the Columns tab.)


-- D. Check: one line per trail and layer.
SELECT txn_sl_tag, layer, count(*) AS rows,
       count(*) FILTER (WHERE upper(status) <> 'SUCCESS') AS not_success,
       count(layered_money) AS with_layered_money
FROM public.layered
GROUP BY txn_sl_tag, layer
ORDER BY txn_sl_tag, layer::int;
