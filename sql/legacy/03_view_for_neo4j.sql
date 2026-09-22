-- =====================================================================
-- KGN4j : the single view Neo4j reads over JDBC.
-- Keep every column name lower-case and unquoted: the JDBC driver hands
-- the labels to APOC exactly as PostgreSQL folds them, and the Cypher
-- in cypher/02_load_from_postgres.cypher expects lower-case keys.
-- =====================================================================

CREATE OR REPLACE VIEW stmt.v_txn_for_graph AS
SELECT
    t.row_key,
    t.unq_id,
    t.from_date,
    t.to_date,
    t.serialno,
    t.txn_date_time,
    t.txn_id,
    t.txn_type,
    t.account_type,
    t.statement_for_acc,
    t.txn_with_acc,
    t.channel,
    t.reference,
    t.txn_type_d_c,
    t.status,
    t.txn_amt,
    t.available_blc_after_txn,
    t.txn_with_info,
    -- ISO text copies of the temporal columns. APOC/JDBC type mapping
    -- differs between drivers, so we hand Neo4j plain strings and let
    -- Cypher build the temporal values itself. Deterministic, no surprises.
    to_char(t.txn_date_time, 'YYYY-MM-DD"T"HH24:MI:SS') AS txn_dt_iso,
    to_char(t.from_date,     'YYYY-MM-DD')              AS from_date_iso,
    to_char(t.to_date,       'YYYY-MM-DD')              AS to_date_iso,
    -- money always flows  from_acc -> to_acc, whichever side the
    -- statement was written from. This is what makes the graph directed.
    CASE WHEN t.txn_type_d_c = 'D' THEN t.statement_for_acc ELSE t.txn_with_acc      END AS from_acc,
    CASE WHEN t.txn_type_d_c = 'D' THEN t.txn_with_acc      ELSE t.statement_for_acc END AS to_acc
FROM stmt.transactions t
WHERE t.txn_type_d_c IS NOT NULL
  AND coalesce(t.txn_with_acc, '') <> '';

-- Optional: a read-only login for Neo4j so you are not putting the
-- postgres superuser password into apoc.conf.
-- CREATE ROLE neo4j_reader LOGIN PASSWORD 'change_me';
-- GRANT CONNECT ON DATABASE kgn4j TO neo4j_reader;
-- GRANT USAGE  ON SCHEMA stmt    TO neo4j_reader;
-- GRANT SELECT ON stmt.v_txn_for_graph TO neo4j_reader;

SELECT * FROM stmt.v_txn_for_graph ORDER BY statement_for_acc, txn_date_time;

-- =====================================================================
-- Per-account summary, also read over JDBC. Having it as a view keeps
-- quoting out of the Cypher, which is worth a lot when the SQL has to
-- survive being nested inside two levels of string literal.
-- =====================================================================
CREATE OR REPLACE VIEW stmt.v_account_summary AS
SELECT
    t.statement_for_acc,
    max(t.account_type)                                              AS account_type,
    count(*)                                                         AS txn_count,
    coalesce(sum(t.txn_amt) FILTER (WHERE t.txn_type_d_c = 'D'), 0)  AS total_debit,
    coalesce(sum(t.txn_amt) FILTER (WHERE t.txn_type_d_c = 'C'), 0)  AS total_credit
FROM stmt.transactions t
GROUP BY t.statement_for_acc;

SELECT * FROM stmt.v_account_summary ORDER BY statement_for_acc;
