"""
KGN4j - build dashboards/kgn4j-dashboard-suspect.json

Usage (from the project root):
    python scripts/build_suspect_dashboard.py

A standalone NeoDash dashboard for the Suspect Network pipeline
(cypher/suspect/). Card queries are read from cypher/suspect/cards/*.cypher.

Nothing else is read or written: kgn4j-dashboard.json (Pathao Pay
drill-down) and kgn4j-dashboard-trail.json (Money Trail) stay as they are.

Needs neodash-patches/kgn4j-suspect-graph.patch for the shapes, the
outside labels, pinned positions and fit-to-view.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'dashboards' / 'kgn4j-dashboard-suspect.json'
CARDS = ROOT / 'cypher' / 'suspect' / 'cards'

# every node label the graph uses; NeoDash matches click rules and
# captions on a node's last label, SNet is listed in case the order flips
NODE_LABELS = ['SNet', 'SStatic', 'SWallets', 'STypeHub', 'SType', 'SMoreTypes', 'SFeeGroup', 'SFeeType',
               'SWallet', 'SWalletOthers', 'SCounterparty', 'SCounterpartyOthers']

# a calm, low-contrast canvas: warm off-white, soft grey links, slate text
CANVAS = {
    'backgroundColor': '#FAFAF7',
    'defaultRelColor': '#C3CBD3',
    'relLabelColor': '#7D8894',
    'nodeLabelColor': '#2F3B45',
}


def q(name):
    return (CARDS / name).read_text(encoding='utf-8')


graph_settings = {
    **CANVAS,
    'layout': 'force-directed',
    'nodeColorProp': 'color',          # set in cypher/suspect/02 section 3.10
    'nodeSizeProp': 'size',
    'nodeOuterLabelProp': 'outer',     # the text beside each node
    # fonts are in graph units, like pin_x / pin_y
    'nodeLabelFontSize': 9,
    'relLabelFontSize': 7,
    'defaultRelWidth': 1.2,
    'showPropertiesOnHover': True,
    'showPropertiesOnClick': True,
    'fixNodeAfterDrag': True,          # drag a node and it stays - survives clicks too
    'pinAllAfterLayout': True,
    'lockable': True,
    'enableExploration': False,
    'enableEditing': False,
    'hideSelections': True,            # no "SNet name" chips under the graph
    'downloadImageEnabled': True,      # camera button: save the graph as an image
    'fullscreenEnabled': True,
    'description': 'Click a transaction type (or More types / Others / a service fee type) to fan out its '
                   'suspected wallets; click a wallet to fan out who it transacted with. Click any base node to '
                   'close. Drag any node to rearrange - it stays put. Scroll to zoom.',
    'actionsRules': [
        {
            'condition': 'onNodeClick',
            'field': label,
            'value': 'click',
            'customization': 'set variable',
            'customizationValue': 'sus_focus',
        }
        for label in NODE_LABELS
    ],
}

selection = {label: 'name' for label in NODE_LABELS}
selection['SFLOW'] = 'name'

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
    'description': 'Rounded box = an account (Agent, Customer, Merchant, TR) or one wallet. Circle = a number '
                   'of wallets; its colour is the status. Hexagon = a transaction type. Diamond = an amount. '
                   'Dashed = "Others", the rest grouped together. Arrows point the way the money or the '
                   'breakdown goes.',
}

dash = {
    'title': 'KGN4j - Suspect Network',
    'version': '2.4',
    'settings': {
        'pagenumber': 0,
        'editable': True,
        'fullscreenEnabled': True,
        'parameters': {'neodash_sus_focus': ''},
        'downloadImageEnabled': True,   # camera in the header: the whole dashboard as an image
        'theme': 'light',
    },
    'pages': [
        {
            'title': 'Suspect Network',
            'reports': [
                {
                    'id': 'sus-legend',
                    'title': 'What the shapes and colours mean',
                    'query': q('legend.cypher'),
                    'width': 5, 'height': 6, 'x': 0, 'y': 0,
                    'type': 'graph',
                    'selection': {'SLegend': 'name'},
                    'settings': legend_settings,
                    'schema': [],
                },
                {
                    'id': 'sus-graph',
                    'title': 'Suspect network',
                    'query': q('graph.cypher'),
                    'width': 19, 'height': 6, 'x': 5, 'y': 0,
                    'type': 'graph',
                    'selection': selection,
                    'settings': graph_settings,
                    'schema': [],
                },
                {
                    'id': 'sus-selected',
                    'title': 'Selected',
                    'query': q('selected.cypher'),
                    'width': 8, 'height': 2, 'x': 0, 'y': 6,
                    'type': 'table',
                    'selection': {},
                    'settings': {'compact': True, 'wrapContent': True},
                    'schema': [],
                },
                {
                    'id': 'sus-types',
                    'title': 'By TXN_TYPE (all types)',
                    'query': q('type_summary.cypher'),
                    'width': 8, 'height': 5, 'x': 0, 'y': 8,
                    'type': 'table',
                    'selection': {},
                    'settings': {'compact': True, 'allowDownload': True, 'defaultPageSize': 10},
                    'schema': [],
                },
                {
                    'id': 'sus-rows',
                    'title': 'Sheet rows (follows the clicked node)',
                    'query': q('rows_table.cypher'),
                    'width': 16, 'height': 7, 'x': 8, 'y': 6,
                    'type': 'table',
                    'selection': {},
                    'settings': {
                        'compact': True,
                        'allowDownload': True,
                        'defaultPageSize': 25,
                        'description': 'Top 2,000 rows by TXN_AMOUNT behind the clicked node '
                                       '(type -> wallet -> counterparty); every row for a base node.',
                    },
                    'schema': [],
                },
                {
                    'id': 'sus-graph-export',
                    'title': 'Graph data (export) - what the graph shows right now',
                    'query': q('graph_export.cypher'),
                    'width': 24, 'height': 5, 'x': 0, 'y': 13,
                    'type': 'table',
                    'selection': {},
                    'settings': {
                        'compact': True,
                        'allowDownload': True,     # CSV download button
                        'downloadImageEnabled': True,
                        'defaultPageSize': 10,
                        'description': 'One row per arrow currently drawn in the graph. Use the download '
                                       'button to save it as CSV.',
                    },
                    'schema': [],
                },
            ],
        }
    ],
    'parameters': {'neodash_sus_focus': ''},
    'extensions': {'active': True, 'activeReducers': [], 'actions': {'active': True}},
}

OUT.write_text(json.dumps(dash, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(f'wrote {OUT.relative_to(ROOT)}')
