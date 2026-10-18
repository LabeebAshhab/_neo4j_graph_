"""
KGN4j - build dashboards/kgn4j-dashboard-layered.json

Usage (from the project root):
    python scripts/build_layered_dashboard.py

A standalone NeoDash dashboard for the Layered Trail pipeline
(cypher/layered/). Card queries are read from cypher/layered/cards/*.cypher.

Nothing else is read or written: kgn4j-dashboard.json, -trail.json and
-suspect.json stay as they are.

Needs neodash-patches/kgn4j-suspect-graph.patch for the shapes, the
outside labels, pinned positions and fit-to-view.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'dashboards' / 'kgn4j-dashboard-layered.json'
CARDS = ROOT / 'cypher' / 'layered' / 'cards'

# every node label the graph uses; NeoDash matches click rules and
# captions on a node's last label, LNet is listed in case the order flips
NODE_LABELS = ['LNet', 'LSource', 'LAccount', 'LExit', 'LHeader']

# the same calm canvas as the Suspect Network dashboard
CANVAS = {
    'backgroundColor': '#FAFAF7',
    'defaultRelColor': '#C3CBD3',
    'relLabelColor': '#56616C',
    'nodeLabelColor': '#2F3B45',
}


def q(name):
    return (CARDS / name).read_text(encoding='utf-8')


graph_settings = {
    **CANVAS,
    'layout': 'force-directed',
    'nodeColorProp': 'color',          # set in cypher/layered/02 section 2.8
    'nodeSizeProp': 'size',
    'relColorProp': 'color',           # grey = fully traced, orange = has a minus
    'relWidthProp': 'width',           # follows the traced amount
    'nodeOuterLabelProp': 'outer',     # the account number beside each node
    'nodeLabelFontSize': 9,
    'relLabelFontSize': 7,
    'showPropertiesOnHover': True,
    'showPropertiesOnClick': True,
    'fixNodeAfterDrag': True,
    'pinAllAfterLayout': True,
    'lockable': True,
    'enableExploration': False,
    'enableEditing': False,
    'hideSelections': True,
    'downloadImageEnabled': True,
    'fullscreenEnabled': True,
    'description': 'P2P only. Starts with each source and the person it paid. Click a person to see who they '
                   'paid next (one layer per click); the path stays open. Click a LAYER header to close '
                   'everything. Arrow captions: traced amount, and in brackets the minus (orange arrows).',
    'actionsRules': [
        {
            'condition': 'onNodeClick',
            'field': label,
            'value': 'click',
            'customization': 'set variable',
            'customizationValue': 'lyr_focus',
        }
        for label in NODE_LABELS
    ],
}

selection = {label: 'name' for label in NODE_LABELS}
selection['LFLOW'] = 'name'

legend_settings = {
    **CANVAS,
    'layout': 'force-directed',
    'nodeColorProp': 'color',
    'nodeSizeProp': 'size',
    'nodeOuterLabelProp': 'outer',
    'nodeLabelFontSize': 9,
    'showPropertiesOnHover': False,
    'showPropertiesOnClick': False,
    'enableExploration': False,
    'enableEditing': False,
    'hideSelections': True,
    'downloadImageEnabled': True,
    'description': 'Hexagon = the source. Circle = a person who paid others on (click to open them); square = '
                   'a person who paid nobody on, the trail ends there. Colour = the layer they received the '
                   'money in; the number inside is the traced amount. Orange arrow = part of that transfer is '
                   'more than the person received, so it is not counted.',
}

table = {'compact': True, 'allowDownload': True}

dash = {
    'title': 'KGN4j - Layered Trail',
    'version': '2.4',
    'settings': {
        'pagenumber': 0,
        'editable': True,
        'fullscreenEnabled': True,
        'parameters': {'neodash_lyr_focus': ''},
        'downloadImageEnabled': True,
        'theme': 'light',
    },
    'pages': [
        {
            'title': 'Layered Trail',
            'reports': [
                {
                    'id': 'lyr-legend',
                    'title': 'What the shapes and colours mean',
                    'query': q('legend.cypher'),
                    'width': 5, 'height': 7, 'x': 0, 'y': 0,
                    'type': 'graph',
                    'selection': {'LLegend': 'name'},
                    'settings': legend_settings,
                    'schema': [],
                },
                {
                    'id': 'lyr-graph',
                    'title': 'Layered money trail',
                    'query': q('graph.cypher'),
                    'width': 19, 'height': 7, 'x': 5, 'y': 0,
                    'type': 'graph',
                    'selection': selection,
                    'settings': graph_settings,
                    'schema': [],
                },
                {
                    'id': 'lyr-selected',
                    'title': 'Selected',
                    'query': q('selected.cypher'),
                    'width': 24, 'height': 2, 'x': 0, 'y': 7,
                    'type': 'table',
                    'selection': {},
                    'settings': {'compact': True, 'wrapContent': True},
                    'schema': [],
                },
                {
                    'id': 'lyr-reconcile',
                    'title': 'Does it add up? (kept by people = layer-1 amount)',
                    'query': q('reconciliation.cypher'),
                    'width': 12, 'height': 3, 'x': 0, 'y': 9,
                    'type': 'table',
                    'selection': {},
                    'settings': {**table, 'defaultPageSize': 10},
                    'schema': [],
                },
                {
                    'id': 'lyr-layers',
                    'title': 'By layer (follows the clicked trail)',
                    'query': q('layer_summary.cypher'),
                    'width': 12, 'height': 3, 'x': 12, 'y': 9,
                    'type': 'table',
                    'selection': {},
                    'settings': {**table, 'defaultPageSize': 10},
                    'schema': [],
                },
                {
                    'id': 'lyr-txns',
                    'title': 'P2P transactions on the arrows shown (TRACED_AMT / MINUS_AMT)',
                    'query': q('txn_table.cypher'),
                    'width': 24, 'height': 6, 'x': 0, 'y': 12,
                    'type': 'table',
                    'selection': {},
                    'settings': {**table, 'defaultPageSize': 25,
                                 'description': 'TRACED_AMT is the part of TXN_AMT that carries the layer-1 '
                                                'money; MINUS_AMT is the rest (orange in the graph).'},
                    'schema': [],
                },
            ],
        }
    ],
    'parameters': {'neodash_lyr_focus': ''},
    'extensions': {'active': True, 'activeReducers': [], 'actions': {'active': True}},
}

OUT.write_text(json.dumps(dash, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f'wrote {OUT.relative_to(ROOT)}')
