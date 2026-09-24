#!/usr/bin/env python3
"""Join SwiftSyntax bodies to LLVM primary regions by exact end position.
Unmatched functions stay unknown. CRAP uses function-local executable lines.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from freshness import snapshot, mismatches

p = argparse.ArgumentParser()
p.add_argument('--coverage', required=True)
p.add_argument('--functions', required=True)
p.add_argument('--output', required=True)
p.add_argument('--gate', action='store_true')
p.add_argument('--manifest')
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
data = json.load(open(a.coverage))['data'][0]
functions = json.load(open(a.functions))

def relative(path):
    path = str(path)
    if '/Sources/' in path:
        return 'Sources/' + path.split('/Sources/', 1)[1]
    return path

sources = {str(f.relative_to(root)) for f in (root / 'Sources').rglob('*.swift')}
files = {relative(f['filename']): f for f in data['files'] if relative(f['filename']) in sources}
indexed = {}
for f in data['functions']:
    if not f['regions']:
        continue
    r = f['regions'][0]
    path = relative(f['filenames'][r[5]])
    if path in sources:
        indexed.setdefault((path, r[2], r[3]), []).append(f)

def line_counts(regions):
    # Partition source locations at every region boundary. The innermost
    # region determines each interval's counter, including zero-hit branches.
    points = sorted({(r[0], r[1]) for r in regions} | {(r[2], r[3]) for r in regions})
    lines = {}
    for left, right in zip(points, points[1:]):
        active = [r for r in regions if (r[0], r[1]) <= left and right <= (r[2], r[3])]
        if not active:
            continue
        inner = sorted(active, key=lambda r: (-r[0], -r[1], r[2], r[3]))[0]
        if inner[7] != 0:
            continue
        last = right[0] - (right[1] == 1)
        for line in range(left[0], last + 1):
            lines[line] = max(lines.get(line, 0), inner[4])
    return lines

for f in functions:
    f['file'] = relative(f['file'])
    candidates = indexed.get((f['file'], f['end_line'], f['end_column']), [])
    candidates = [c for c in candidates if
                  (f['start_line'], f['start_column']) <= tuple(c['regions'][0][:2])
                  and c['regions'][0][0] <= f['body_start_line']]
    # Swift emits an autoclosure wrapper for `optional ?? { ... }` with
    # the same source extent. Invoking the wrapper does not invoke the closure.
    if f['kind'] == 'closure':
        closure_candidates = [c for c in candidates if re.search(r'cfU[0-9]*_$', c['name'])]
        if closure_candidates:
            candidates = closure_candidates
    combined = {}
    for candidate in candidates:
        for line, count in line_counts(candidate['regions']).items():
            combined[line] = max(combined.get(line, 0), count)
    if combined:
        f.update(coverage_basis='LLVM function-local line regions; exact syntax end boundary',
                 covered_lines=sorted(k for k, v in combined.items() if v > 0),
                 executable_lines=sorted(combined), llvm_functions=[c['name'] for c in candidates])
        f['coverage_fraction'] = len(f['covered_lines']) / len(combined)
        c = f['complexity']
        f['crap'] = c*c*(1-f['coverage_fraction'])**3+c
    else:
        f.update(coverage_basis='unmapped', coverage_fraction=None, crap=None, llvm_functions=[])

line_total = sum(f['summary']['lines']['count'] for f in files.values())
line_hit = sum(f['summary']['lines']['covered'] for f in files.values())
branch_total = sum(f['summary']['branches']['count'] for f in files.values())
branch_hit = sum(f['summary']['branches']['covered'] for f in files.values())
scored = [f for f in functions if f['crap'] is not None]
report = dict(schema='zoomies-quality/v2', component='Zoomies app',
    scope='All handwritten Sources/**/*.swift; excludes tests, dependencies and generated SwiftPM code',
    complexity_method='SwiftSyntax: base 1; if/guard/loop/catch/non-default switch case/ternary +1; extra comma conditions and &&/||/?? +1; nested closures/declarations scored separately',
    source_files=sorted(sources),
    declaration_only_files=sorted(path for path in sources-files.keys() if not any(f['file']==path for f in functions)),
    missing_coverage_files=sorted(path for path in sources-files.keys() if any(f['file']==path for f in functions)),
    coverage=dict(lines=dict(covered=line_hit, total=line_total, percent=100*line_hit/line_total),
                  branches=dict(covered=branch_hit, total=branch_total, percent=100*branch_hit/branch_total if branch_total else None,
                                verified=branch_total > 0)),
    summary=dict(function_bodies=len(functions), unmapped=len(functions)-len(scored),
                 max_complexity=max(f['complexity'] for f in functions), complexity_gt8=sum(f['complexity']>8 for f in functions),
                 max_crap=max(f['crap'] for f in scored), crap_gt8=sum(f['crap']>8 for f in scored)),
    file_coverage={k:v['summary'] for k,v in files.items()}, functions=functions,
    input_sha256={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in [a.coverage,a.functions]})
changed = mismatches(json.load(open(a.manifest)), snapshot()) if a.manifest else None
report['freshness'] = dict(verified=changed == [], changed_inputs=changed, manifest=a.manifest)
report['targets_met'] = (changed == [] and report['coverage']['lines']['percent'] >= 90 and branch_total > 0 and
                          100*branch_hit/branch_total >= 85 and not report['missing_coverage_files'] and
                          report['summary']['unmapped'] == 0 and report['summary']['crap_gt8'] == 0)
Path(a.output).write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['coverage','summary','missing_coverage_files','freshness','targets_met']}, indent=2))
if a.gate and not report['targets_met']:
    raise SystemExit(1)
