#!/usr/bin/env python3
"""Sammelt alle übersetzbaren Texte aus dem Swift-Code und prüft, ob es für jeden
eine englische Übersetzung gibt. Aufruf: python3 Support/tools/check_strings.py [--list]"""
import re, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIT = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [
    r'\bL\(\s*' + LIT,
    r'\b(?:Text|Button|Label|Toggle|Section|TextField|LabeledContent|Picker|Menu|ContentUnavailableView)\(\s*' + LIT,
    r'\.(?:help|confirmationDialog|alert)\(\s*' + LIT,
    r'prompt:\s*' + LIT,
    r'\b(?:label|hint|placeholder|addLabel|title):\s*' + LIT,
    r'var (?:placeholder|addLabel) = ' + LIT,
    r'case \w+ = ' + LIT,
    r'\(\s*' + LIT + r',\s*"[a-z.0-9]+",\s*\w+\)',          # filledSections-Tupel
    r'sectionLabel\(\s*' + LIT,
]

def keys():
    found = {}
    for f in glob.glob(os.path.join(ROOT, 'Sources/note4meet/*.swift')):
        for line in open(f, encoding='utf-8'):
            code = line.split(' //')[0]
            if code.strip().startswith('//') or 'Text(verbatim' in code and 'L(' not in code:
                continue
            for p in PATTERNS:
                for m in re.finditer(p, code):
                    s = m.group(1)
                    if '\\(' in s or not re.search(r'[A-Za-zÄÖÜäöü]', s):
                        continue
                    found.setdefault(s, os.path.basename(f))
    return found

def strings_file(lang):
    path = os.path.join(ROOT, f'Support/{lang}.lproj/Localizable.strings')
    if not os.path.exists(path):
        return {}
    txt = open(path, encoding='utf-8').read()
    return dict(re.findall(r'^' + LIT + r'\s*=\s*' + LIT + ';', txt, re.M))

if __name__ == '__main__':
    k = keys()
    if '--list' in sys.argv:
        for s, f in sorted(k.items(), key=lambda x: (x[1], x[0])):
            print(f'{f}\t{s}')
        sys.exit(0)
    en = strings_file('en')
    missing = [s for s in k if s not in en]
    unused = [s for s in en if s not in k]
    print(f'{len(k)} Texte im Code, {len(en)} Übersetzungen')
    for s in missing: print('FEHLT:', s)
    for s in unused: print('UNBENUTZT:', s)
    sys.exit(1 if missing else 0)
