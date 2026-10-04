// CARD - "Trace rule" (report type: Table)
// Click a RULE button to set $neodash_trace_mode.
UNWIND [
  {m: 'credit_first', d: 'Debits after the credit are paid from THIS credit first'},
  {m: 'fifo',         d: 'Money already in the account is spent first, then this credit'}
] AS r
RETURN CASE WHEN r.m = coalesce($neodash_trace_mode, 'credit_first') THEN '(*) ' ELSE '( ) ' END + r.m AS RULE,
       r.d AS MEANING,
       r.m AS __mode
