#!/usr/bin/env python3
"""Independent fixtures for parser boundaries and coverage-join failure modes."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from freshness import snapshot, mismatches

ROOT = Path(__file__).resolve().parents[1]
PARSER = str(Path(sys.argv.pop(1)).resolve())

class MeasurementTests(unittest.TestCase):
    def test_freshness_detects_edits_added_removed_sources_and_test_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'Sources').mkdir()
            (root/'Tests').mkdir()
            source = root/'Sources/One.swift'
            source.write_text('func one() {}')
            test = root/'Tests/One.swift'
            test.write_text('test original')
            saved = snapshot(root)
            self.assertEqual(mismatches(saved, snapshot(root)), [])
            source.write_text('func changed() {}')
            test.write_text('test changed')
            (root/'Sources/Two.swift').write_text('func two() {}')
            self.assertEqual(mismatches(saved, snapshot(root)), ['Sources/One.swift', 'Sources/Two.swift', 'Tests/One.swift'])
            source.unlink()
            self.assertIn('Sources/One.swift', mismatches(saved, snapshot(root)))

    def test_nested_bodies_are_separate_and_do_not_inflate_parent(self):
        source = '''func outer(_ a: Bool, _ b: Bool) {
    if a && b { print("outer") }
    let closure = { if a { print("closure") } }
    func nested() { if b { print("nested") } }
}
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixture.swift'
            path.write_text(source)
            rows = json.loads(subprocess.check_output([PARSER, str(path)]))
        actual = {(r['name'], r['kind']): (r['complexity'], r['start_line'], r['end_line']) for r in rows}
        self.assertEqual(actual, {('outer','function'):(3,1,5), ('closure','closure'):(2,3,3), ('nested','function'):(2,4,4)})

    def run_join(self, rows, llvm):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            file = str(ROOT / 'Sources/ImageSafety.swift')
            data = {'data':[{'files':[{'filename':file,'summary':{'lines':{'count':5,'covered':3,'percent':60},
                              'branches':{'count':0,'covered':0,'percent':0}}}], 'functions':llvm}]}
            (folder/'coverage.json').write_text(json.dumps(data))
            (folder/'functions.json').write_text(json.dumps(rows))
            subprocess.run([sys.executable, str(ROOT/'quality/metrics.py'), '--coverage',str(folder/'coverage.json'),
                            '--functions',str(folder/'functions.json'),'--output',str(folder/'metrics.json')],
                           check=True, stdout=subprocess.DEVNULL)
            return json.loads((folder/'metrics.json').read_text())

    def row(self, **changes):
        return dict(file='Sources/ImageSafety.swift',name='fixture',kind='function',start_line=1,start_column=1,
                    end_line=6,end_column=1,body_start_line=1,complexity=2,**changes)

    def llvm(self, name, count, regions=None):
        return dict(name=name,count=count,filenames=[str(ROOT/'Sources/ImageSafety.swift')],
                    regions=regions or [[1,1,6,1,count,0,0,0]])

    def test_zero_hit_inner_regions_and_unmapped_bodies_stay_uncovered(self):
        mapped = self.row()
        unknown = dict(mapped, name='unknown', end_line=9)
        llvm = self.llvm('fixture',1,[[1,1,6,1,1,0,0,0],[3,1,5,1,0,0,0,0]])
        report = self.run_join([mapped, unknown], [llvm])
        scored, unscored = report['functions']
        self.assertEqual(scored['covered_lines'], [1,2,5])
        self.assertEqual(scored['executable_lines'], [1,2,3,4,5])
        self.assertAlmostEqual(scored['crap'], 2.256)
        self.assertIsNone(unscored['crap'])
        self.assertIsNone(unscored['coverage_fraction'])
        self.assertEqual(report['summary']['unmapped'], 1)
        self.assertIsNone(report['coverage']['branches']['percent'])
        self.assertFalse(report['targets_met'])

    def test_invoked_autoclosure_wrapper_does_not_cover_returned_closure(self):
        row = dict(self.row(), kind='closure')
        report = self.run_join([row], [self.llvm('wrapperXEfu_', 1), self.llvm('returnedcfU_', 0)])
        result = report['functions'][0]
        self.assertEqual(result['coverage_fraction'], 0)
        self.assertEqual(result['crap'], 6)
        self.assertEqual(result['llvm_functions'], ['returnedcfU_'])

unittest.main()
