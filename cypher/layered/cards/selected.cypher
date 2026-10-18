// CARD - "Selected" (report type: Table, single row)
// The clicked person: the traced money they received, how many people
// they paid, what they sent, the minus, and what they kept.
WITH coalesce($neodash_lyr_focus, '') AS fk
OPTIONAL MATCH (f:LNet {key: fk})
RETURN CASE WHEN f IS NULL OR f:LHeader THEN 'nothing clicked' ELSE f.role END AS NODE,
       coalesce(f.acc, '')                AS ACCOUNT,
       f.tag                              AS TXN_SL_TAG,
       f.layer                            AS LAYER,
       round(f.traced_in, 2)              AS TRACED_IN,
       round(f.received, 2)               AS RECEIVED_P2P,
       f.pays                             AS PAYS_PEOPLE,
       round(f.sent, 2)                   AS SENT_P2P,
       round(f.traced_out, 2)             AS TRACED_OUT,
       round(f.excess, 2)                 AS MINUS_NOT_TRACED,
       round(f.kept, 2)                   AS KEPT,
       CASE WHEN size(coalesce(f.also_in_layers, [])) = 0 THEN ''
            ELSE reduce(s = '', l IN f.also_in_layers | CASE WHEN s = '' THEN '' ELSE s + ', ' END + toString(l))
       END                                AS ALSO_IN_LAYERS
