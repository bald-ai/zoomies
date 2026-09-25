#!/usr/bin/env python3
"""Bind measurements to all production, test and measurement-tool inputs."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def snapshot(root=ROOT):
    paths = set()
    for directory, suffixes in [('Sources', {'.swift'}), ('Tests', {'.swift'}),
                                ('quality', {'.py', '.swift', '.sh'})]:
        paths.update(p for p in (root / directory).rglob('*') if p.suffix in suffixes)
    paths.update(p for p in [root/'Package.swift', root/'Package.resolved'] if p.exists())
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

def mismatches(saved, current):
    return sorted(p for p in saved.keys() | current.keys() if saved.get(p) != current.get(p))

if __name__ == '__main__':
    mode, filename = sys.argv[1:]
    path = Path(filename)
    if mode == 'capture':
        path.write_text(json.dumps(snapshot(), indent=2) + '\n')
    elif mode == 'verify':
        changed = mismatches(json.loads(path.read_text()), snapshot())
        if changed:
            print('Stale measurement inputs: ' + ', '.join(changed))
            sys.exit(1)
        print('Measurement input hashes match current tree.')
    else:
        raise SystemExit('Expected capture or verify')
