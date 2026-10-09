#!/usr/bin/env python3
"""Copies the app's Features tab into the site: groups, switches, shortcuts, copy in four languages and the
default on/off state of every switch. Reads Sources/SAVISUL/FeaturesPane.swift and Suite/SuiteSettings.swift,
writes site/assets/js/features-data.js. Run it after changing either file."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANE = (ROOT / 'Sources/SAVISUL/FeaturesPane.swift').read_text()
SETTINGS = (ROOT / 'Sources/SAVISUL/Suite/SuiteSettings.swift').read_text()
L10N = (ROOT / 'Sources/SAVISUL/L10n.swift').read_text()
OUT = ROOT / 'site/assets/js/features-data.js'

S = r'"((?:[^"\\]|\\.)*)"'
PHRASE = rf'Phrase\({S},\s*ru:\s*{S},\s*uk:\s*{S},\s*fr:\s*{S}\)'
ITEM = re.compile(rf'FeatureItem\(id:\s*"(\w+)",\s*key:\s*\\\.(\w+),\s*title:\s*{PHRASE}'
                  rf'(?:,\s*detail:\s*{PHRASE})?(?:,\s*keys:\s*\[([^\]]*)\])?\)')


def text(raw):
    return json.loads(f'"{raw}"')


def phrase(groups):
    en, ru, uk, fr = (text(g) for g in groups)
    return {'en': en, 'ru': ru, 'uk': uk, 'fr': fr}


def item(match):
    g = match.groups()
    out = {'id': g[0], 'key': g[1], 'title': phrase(g[2:6])}
    if g[6] is not None:
        out['detail'] = phrase(g[6:10])
    if g[10]:
        out['keys'] = [text(k) for k in re.findall(S, g[10])]
    return out


groups = []
body = PANE[PANE.index('static let all: [FeatureGroup]'):PANE.index('/// How many features are running')]
for chunk in body.split('FeatureGroup(')[1:]:
    head = re.search(rf'id:\s*"(\w+)",\s*symbol:\s*"([^"]+)",\s*title:\s*{PHRASE},\s*detail:\s*{PHRASE}', chunk)
    items = [item(m) for m in ITEM.finditer(chunk)]
    needs = re.search(r'needs:\s*\.(\w+)', chunk)
    g = head.groups()
    groups.append({'id': g[0], 'symbol': g[1], 'title': phrase(g[2:6]), 'detail': phrase(g[6:10]),
                   'main': items[0], 'options': items[1:], 'needs': needs.group(1) if needs else 'nothing'})

phrases = {}
enum = PANE[PANE.index('enum FeaturePhrases'):]
for m in re.finditer(rf'static let (\w+) = {PHRASE}', enum):
    phrases[m.group(1)] = phrase(m.groups()[1:5])
for m in re.finditer(rf'static func (\w+)\([^)]*\) -> String \{{\s*{PHRASE}', enum):
    phrases[m.group(1)] = phrase(m.groups()[1:5])

# The tab name and the "N of M turned on" line live in the app's string tables, one per language in this order.
strings = {}
for key in ['tabFeatures', 'featuresSubtitle']:
    found = [text(v) for v in re.findall(rf'\.{key}:\s*{S}', L10N)]
    assert len(found) == 4, f'{key}: expected 4 languages, found {len(found)}'
    strings[key] = dict(zip(['en', 'ru', 'uk', 'fr'], found))

defaults = {m.group(1): m.group(2) == 'true' for m in re.finditer(r'(\w+) = Self\.read\("\w+", (true|false)\)', SETTINGS)}
keys = {i['key'] for g in groups for i in [g['main'], *g['options']]}
missing = keys - defaults.keys()
assert not missing, f'no default for {missing}'

OUT.write_text(
    '// The Features tab, generated from Sources/SAVISUL/FeaturesPane.swift and SuiteSettings.swift by\n'
    '// tools/site-features.py. Do not edit by hand.\n'
    f'export const FEATURE_GROUPS = {json.dumps(groups, ensure_ascii=False, indent=1)};\n\n'
    f'export const FEATURE_DEFAULTS = {json.dumps({k: defaults[k] for k in sorted(keys)}, indent=1)};\n\n'
    f'export const FEATURE_PHRASES = {json.dumps(phrases, ensure_ascii=False, indent=1)};\n\n'
    f'export const FEATURE_STRINGS = {json.dumps(strings, ensure_ascii=False, indent=1)};\n')
print(f'{len(groups)} groups, {sum(1 + len(g["options"]) for g in groups)} switches, {len(phrases)} phrases -> {OUT.relative_to(ROOT)}')
