// =====================================================================
// KGN4j - diagnose a load that is not working.
//
// Read-only. Changes nothing, safe to run at any time.
//
//   & "$NEO\bin\cypher-shell.bat" -a bolt://localhost:7687 -u neo4j -p YOUR_PASSWORD -d neo4j --file cypher/00_diagnose.cypher
//
// Read the four sections in order and stop at the first one that is
// wrong - the later ones depend on the earlier ones.
// =====================================================================


// ---------------------------------------------------------------------
// 1. Did the config actually take effect?
//
//    Expect on a 16 GB machine:
//      server.memory.heap.max_size          4.00GiB
//      server.memory.pagecache.size         6.00GiB
//      dbms.memory.transaction.total.max    2.00GiB
//      db.memory.transaction.max            0B
//      server.directories.import            <NEO4J_HOME>\import
//
//    Anything else means the file was not saved, Neo4j was not
//    restarted, or a duplicate uncommented key is overriding it.
// ---------------------------------------------------------------------
SHOW SETTINGS YIELD name, value
WHERE name IN ['server.memory.heap.max_size',
               'server.memory.pagecache.size',
               'dbms.memory.transaction.total.max',
               'db.memory.transaction.max',
               'server.directories.import']
RETURN name, value
ORDER BY name;


// ---------------------------------------------------------------------
// 2. Can Neo4j actually see and read the two CSVs?
//
//    Three rows of real data = the file is there and readable.
//
//    "Couldn't load the external resource"  -> the file is NOT in
//    <NEO4J_HOME>\import. That is step 4 of the setup, and it has to be
//    done on THIS machine - the CSVs are not in the repo.
// ---------------------------------------------------------------------
LOAD CSV WITH HEADERS FROM 'file:///txn_for_graph.csv' AS row
WITH row LIMIT 3
RETURN row.statement_for_acc AS statement_for_acc,
       row.txn_id            AS txn_id,
       row.txn_type_d_c      AS d_c,
       row.txn_amt           AS amount;


LOAD CSV WITH HEADERS FROM 'file:///account_summary.csv' AS row
WITH row LIMIT 3
RETURN row.statement_for_acc AS statement_for_acc,
       row.txn_count         AS txn_count;


// ---------------------------------------------------------------------
// 3. What is in the database right now?
//
//    Nothing at all      -> the load never ran, or it wiped and failed
//                           on the very first batch
//    Some Transactions   -> it died partway; re-run 02b, it starts by
//                           clearing, so a partial load is not a problem
//    ~6.7M Transactions  -> the load WORKED, go straight to 03
// ---------------------------------------------------------------------
MATCH (n)
RETURN labels(n) AS label, count(*) AS nodes
ORDER BY label;


// ---------------------------------------------------------------------
// 4. Are the indexes from 01_constraints present?
//
//    Expect 3 constraints and 8 indexes (plus the constraint-backing
//    ones). If they are missing, 02b still works but degrades from
//    ~20 minutes to hours, because every MERGE becomes a full scan.
// ---------------------------------------------------------------------
SHOW CONSTRAINTS YIELD name, labelsOrTypes, properties
RETURN name, labelsOrTypes, properties
ORDER BY name;

SHOW INDEXES YIELD name, labelsOrTypes, properties, state
RETURN name, labelsOrTypes, properties, state
ORDER BY name;
