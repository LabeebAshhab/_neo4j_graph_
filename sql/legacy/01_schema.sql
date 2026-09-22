-- =====================================================================
-- KGN4j : PostgreSQL schema
-- Run this in pgAdmin against a database called  kgn4j
-- (create it first:  CREATE DATABASE kgn4j;)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS stmt;

-- ---------------------------------------------------------------------
-- 1. STAGING TABLE - every column is TEXT.
--    Import the CSV straight into this table with the pgAdmin
--    Import/Export dialog. Nothing can fail on a bad date or a comma
--    inside an amount, because nothing is being parsed yet.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stmt.txn_stage;

CREATE TABLE stmt.txn_stage (
    unq_id                   TEXT,
    from_date                TEXT,
    to_date                  TEXT,
    serialno                 TEXT,
    txn_date_time            TEXT,
    txn_id                   TEXT,
    txn_type                 TEXT,
    account_type             TEXT,
    statement_for_acc        TEXT,
    txn_with_acc             TEXT,
    channel                  TEXT,
    reference                TEXT,
    txn_type_d_c             TEXT,
    status                   TEXT,
    txn_amt                  TEXT,
    available_blc_after_txn  TEXT,
    txn_with_info            TEXT
);

-- ---------------------------------------------------------------------
-- 2. TYPED TABLE - this is what Neo4j actually reads.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stmt.transactions;

CREATE TABLE stmt.transactions (
    unq_id                   TEXT,
    from_date                DATE,
    to_date                  DATE,
    serialno                 INTEGER,
    txn_date_time            TIMESTAMP,
    txn_id                   TEXT,
    txn_type                 TEXT,
    account_type             TEXT,
    statement_for_acc        TEXT NOT NULL,
    txn_with_acc             TEXT,
    channel                  TEXT,
    reference                TEXT,
    txn_type_d_c             CHAR(1),          -- normalised to 'D' or 'C'
    status                   TEXT,
    txn_amt                  NUMERIC(20,2),
    available_blc_after_txn  NUMERIC(20,2),
    txn_with_info            TEXT,
    row_key                  TEXT PRIMARY KEY  -- stable unique id for MERGE in Neo4j
);

CREATE INDEX IF NOT EXISTS ix_txn_stmt_acc ON stmt.transactions (statement_for_acc);
CREATE INDEX IF NOT EXISTS ix_txn_with_acc ON stmt.transactions (txn_with_acc);
CREATE INDEX IF NOT EXISTS ix_txn_dc       ON stmt.transactions (txn_type_d_c);
CREATE INDEX IF NOT EXISTS ix_txn_dt       ON stmt.transactions (txn_date_time);

-- ---------------------------------------------------------------------
-- 3. Helper: tolerant timestamp / date / numeric parsers.
--    Bank statement exports are never consistent, so we try a list of
--    formats instead of assuming one.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stmt.safe_ts(p TEXT)
RETURNS TIMESTAMP LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    f TEXT;
    formats TEXT[] := ARRAY[
        'YYYY-MM-DD HH24:MI:SS',
        'YYYY-MM-DD"T"HH24:MI:SS',
        'DD/MM/YYYY HH24:MI:SS',
        'MM/DD/YYYY HH24:MI:SS',
        'DD-MON-YYYY HH24:MI:SS',
        'DD-MM-YYYY HH24:MI:SS',
        'YYYY/MM/DD HH24:MI:SS',
        'YYYY-MM-DD',
        'DD/MM/YYYY',
        'MM/DD/YYYY',
        'DD-MON-YYYY'
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
END $$;

CREATE OR REPLACE FUNCTION stmt.safe_num(p TEXT)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    cleaned TEXT;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN 0; END IF;
    -- strip thousands separators, currency symbols and spaces
    cleaned := regexp_replace(btrim(p), '[^0-9.\-]', '', 'g');
    IF cleaned IN ('', '-', '.') THEN RETURN 0; END IF;
    RETURN cleaned::NUMERIC;
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END $$;
