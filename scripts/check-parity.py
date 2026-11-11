#!/usr/bin/env python3
"""Checks that macos/ and windows/ have not drifted apart where a machine can tell.

  1. Generated files match shared/ (scripts/generate.py --check).
  2. Every Russian interface string of both platforms (Swift, C# and the Windows shell) has English in shared/strings/en.txt.
  3. Every SF Symbol name used on macOS has a Segoe Fluent pair in shared/glyphs.json.
  4. The version in shared/version.txt matches macos/Resources/App/Info.plist.
  5. Every keyboard command in shared/keymap.json has a Windows shortcut or is explicitly empty on both.

Behaviour parity is checked by shared/fixtures/core/vectors.json in both test suites; docs/PARITY.md lists
what differs on purpose. Exit code 1 lists every problem.
"""
import json, pathlib, re, subprocess, sys

root = pathlib.Path(__file__).resolve().parent.parent
problems = []

result = subprocess.run([sys.executable, str(root / 'scripts' / 'generate.py'), '--check'], capture_output=True, text=True)
if result.returncode != 0: problems.append(result.stderr.strip() or result.stdout.strip())

table = {line.split('⟩')[0] for line in (root / 'shared/strings/en.txt').read_text().split('\n') if line.count('⟩') == 2}
pair = re.compile(r'(?:\btext|\bText|\bT)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"')
missing = {}
for folder, pattern in (('macos/Sources/MicaApp', '*.swift'), ('windows/src', '*.cs'), ('windows/shell/js', '*.js')):
    for path in (root / folder).rglob(pattern):
        if '/obj/' in str(path) or '/bin/' in str(path) or '/gen/' in str(path): continue
        for match in pair.finditer(path.read_text()):
            regular = match.group(2).encode().decode('unicode_escape').encode('latin-1').decode('utf-8') if '\\' in match.group(2) else match.group(2)
            if re.search('[а-яА-ЯёЁ]', regular) and regular not in table:
                missing.setdefault(regular, str(path.relative_to(root)))
for regular, where in sorted(missing.items()):
    problems.append(f'no English for {regular!r} ({where})')

glyphs = json.loads((root / 'shared/glyphs.json').read_text())['glyphs']
symbol = re.compile(r'(?:systemName|symbol|symbols|Glyph\(name)\s*:\s*\[?"([a-z][a-z0-9.]*)"')
for path in (root / 'macos/Sources/MicaApp').rglob('*.swift'):
    for name in symbol.findall(path.read_text()):
        if '.' in name and name.split('.')[-1] in ('json', 'txt', 'vault', 'app', 'org', 'com', 'quarantine', 'passwords', 'web', 'incognito'): continue
        if name not in glyphs and name != 'mica.incognito':
            problems.append(f'SF Symbol {name!r} has no Windows glyph in shared/glyphs.json ({path.relative_to(root)})')

for name in json.loads((root / 'shared/profiles.json').read_text())['icons']:
    if name not in glyphs: problems.append(f'profile icon {name!r} has no Windows glyph in shared/glyphs.json')

version = (root / 'shared/version.txt').read_text().strip()
plist = (root / 'macos/Resources/App/Info.plist').read_text()
found = re.search(r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>', plist)
if not found or found.group(1) != version:
    problems.append(f'version: shared/version.txt is {version}, Info.plist is {found.group(1) if found else "missing"}')

keymap = json.loads((root / 'shared/keymap.json').read_text())['commands']
for command, keys in keymap.items():
    if keys['macos'] and not keys['windows']: problems.append(f'keymap: {command} has a macOS shortcut but none on Windows')

if problems:
    print('\n'.join(problems))
    sys.exit(1)
print('parity checks passed')
