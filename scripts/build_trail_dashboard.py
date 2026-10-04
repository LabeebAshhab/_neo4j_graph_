"""
KGN4j - build dashboards/kgn4j-dashboard-trail.json

Usage (from the project root):
    python scripts/build_trail_dashboard.py

The new dashboard = the ORIGINAL drill-down page (queries untouched, only
the graph's layout/drag settings changed) + a new "Money Trail" page whose
card queries are read from cypher/trace/*.cypher.

dashboards/kgn4j-dashboard.json is only READ here, never written - it stays
the way back to the previous graph.
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT / 'dashboards' / 'kgn4j-dashboard.json'
OUT = ROOT / 'dashboards' / 'kgn4j-dashboard-trail.json'
TRACE = ROOT / 'cypher' / 'trace'


def q(name):
    return (TRACE / name).read_text(encoding='utf-8')


def click_rule(field, value, variable):
    return {
        'condition': 'Click',
        'field': field,
        'value': value,
        'customization': 'set variable',
        'customizationValue': variable,
    }


original = json.loads(ORIGINAL.read_text(encoding='utf-8'))
dash = copy.deepcopy(original)
dash['title'] = 'KGN4j - Pathao Pay drill-down + Money Trail'

# --- page 1: the existing drill-down, graph made readable + drag-one-node ---
drill = dash['pages'][0]
for report in drill['reports']:
    # the one-row breadcrumb card needs 2 rows, not 3; the freed row moves
    # the graph up so more of it is on screen
    if report['id'] == 'kgn4j-breadcrumb':
        report['height'] = 2
    elif report['y'] >= 3:
        report['y'] -= 1
    if report['type'] == 'graph':
        report['settings']['pinAllAfterLayout'] = True   # re-layout + fit on every click, then pin
        report['settings']['fixNodeAfterDrag'] = True    # a dragged node stays where it is dropped

# --- page 2: Money Trail ----------------------------------------------------
trail_graph_settings = {
    'layout': 'tree-top-down',
    # a vertical chain of up to ~16 nodes is fitted into the card, so text is
    # sized relative to the level distance, not in absolute pixels
    'graphDepthSep': 30,
    'nodeColorScheme': 'category10',
    'nodeLabelFontSize': 6.5,
    'relLabelFontSize': 5,
    'defaultNodeSize': 6,
    'defaultRelWidth': 1.5,
    'showPropertiesOnHover': True,
    'showPropertiesOnClick': True,
    'fixNodeAfterDrag': True,
    'pinAllAfterLayout': True,
    'lockable': True,
    'enableExploration': False,
    'enableEditing': False,
    'description': 'Credit at the top, each debit that used it below, in date-time order. '
                   'The last node says where the credited amount terminated.',
}

trail = {
    'title': 'Money Trail',
    'reports': [
        {
            'id': 'trail-pick-customer',
            'title': '1. Pick a customer',
            'query': q('pick_customer.cypher'),
            'width': 3, 'height': 5, 'x': 0, 'y': 0,
            'type': 'table',
            'selection': {},
            'settings': {
                'compact': True,
                'description': 'Click a CUSTOMER button. Counts are real statement lines (source duplicates removed).',
                'actionsRules': [click_rule('CUSTOMER', 'ACCOUNT', 'trace_acc')],
                'defaultPageSize': 10,
            },
            'schema': [],
        },
        {
            'id': 'trail-pick-credit',
            'title': '2. Pick a credit to trace',
            'query': q('pick_credit.cypher'),
            'width': 5, 'height': 5, 'x': 3, 'y': 0,
            'type': 'table',
            'selection': {},
            'settings': {
                'compact': True,
                'allowDownload': True,
                'description': "Every credit into the selected customer's account, oldest first. "
                               'Click TRACE. Use the column filter to find a date or amount.',
                'actionsRules': [click_rule('TRACE', '__key', 'trace_credit')],
                'defaultPageSize': 10,
            },
            'schema': [],
        },
        {
            'id': 'trail-rule',
            'title': 'Trace rule',
            'query': q('pick_rule.cypher'),
            'width': 4, 'height': 3, 'x': 8, 'y': 0,
            'type': 'table',
            'selection': {},
            'settings': {
                'compact': True,
                'description': 'credit_first: debits after the credit are paid from it first. '
                               'fifo: older balance is spent first.',
                'actionsRules': [click_rule('RULE', '__mode', 'trace_mode')],
            },
            'schema': [],
        },
        {
            'id': 'trail-summary',
            'title': 'Where did it terminate?',
            'query': q('trace_summary.cypher'),
            'width': 4, 'height': 10, 'x': 8, 'y': 3,
            'type': 'table',
            'selection': {},
            'settings': {
                'compact': True,
                'wrapContent': True,
                'description': 'When and on which debit the credited amount was fully used.',
                'defaultPageSize': 25,
            },
            'schema': [],
        },
        {
            'id': 'trail-graph',
            'title': 'Money trail',
            'query': q('trace_graph.cypher'),
            'width': 8, 'height': 8, 'x': 0, 'y': 5,
            'type': 'graph',
            'selection': {
                'TraceSource': 'name',
                'TraceCredit': 'name',
                'TraceStep': 'name',
                'TraceGap': 'name',
                'TraceEnd': 'name',
                'CREDITED': 'name',
                'SPENT': 'name',
                'ENDS': 'name',
            },
            'settings': trail_graph_settings,
            'schema': [],
        },
        {
            'id': 'trail-steps',
            'title': 'Money trail - every step',
            'query': q('trace_table.cypher'),
            'width': 12, 'height': 6, 'x': 0, 'y': 13,
            'type': 'table',
            'selection': {},
            'settings': {
                'compact': True,
                'allowDownload': True,
                'description': 'Every debit that used part of the credit, in date-time order. '
                               'FROM_THIS_CREDIT is exact to 0.000001 tk.',
                'defaultPageSize': 25,
            },
            'schema': [],
        },
    ],
}
dash['pages'].append(trail)

# NeoDash's grid is 24 columns wide, but every card above was sized for 12,
# so the dashboard only ever used the left half of the window. Double the
# horizontal sizes on both pages so the cards - and the graphs - fill it.
for page in dash['pages']:
    for report in page['reports']:
        report['x'] *= 2
        report['width'] *= 2

params = {
    'neodash_focus': 'root',
    'neodash_trace_acc': '',
    'neodash_trace_credit': '',
    'neodash_trace_mode': 'credit_first',
}
dash['settings']['parameters'] = dict(params)
dash['parameters'] = dict(params)

OUT.write_text(json.dumps(dash, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f'wrote {OUT.relative_to(ROOT)}')
