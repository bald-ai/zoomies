"""Regression checks for disposable verification data; never run real metrics/mutations."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verification_session', Path(__file__).with_name('verification-session.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class VerificationSessionTests(unittest.TestCase):
    def test_success_and_failure_leave_no_output_or_lock(self):
        for code in (0, 7):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                command = [sys.executable, '-c',
                           f"from pathlib import Path; Path('reports/result.json').write_text('temporary'); raise SystemExit({code})"]
                self.assertEqual(runner.run_session([command], ['reports'], root=root), code)
                self.assertFalse((root / 'reports').exists())
                self.assertFalse((root / '.verification-session').exists())

    def test_coverage_summary_runs_after_tests(self):
        commands = runner.CONFIG['commands']['coverage']
        self.assertEqual(commands[0][:2], ['swift', 'test'])
        self.assertEqual(commands[1][:3], ['xcrun', 'llvm-cov', 'report'])
        self.assertIn('-instr-profile=.build/debug/codecov/default.profdata', commands[1])

    def test_coverage_data_is_available_to_report_then_cleaned_on_success_or_failure(self):
        for report_code in (0, 7):
            with self.subTest(report_code=report_code), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                counters = root / '.build/debug/codecov'
                generate = [sys.executable, '-c',
                            "from pathlib import Path; p=Path('.build/debug/codecov'); "
                            "p.mkdir(parents=True); (p/'default.profdata').write_text('counters')"]
                report = [sys.executable, '-c',
                          "from pathlib import Path; "
                          "assert Path('.build/debug/codecov/default.profdata').read_text() == 'counters'; "
                          f"print('Coverage summary'); raise SystemExit({report_code})"]
                self.assertEqual(runner.run_session([generate, report], ['reports'],
                                                   root=root, coverage=True), report_code)
                self.assertFalse(counters.exists())
                self.assertFalse((root / 'reports').exists())
                self.assertFalse((root / '.verification-session').exists())

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'reports').mkdir()
            (root / 'reports/keep').write_text('existing')
            with self.assertRaises(RuntimeError):
                runner.run_session([], ['reports'], root=root)
            self.assertEqual((root / 'reports/keep').read_text(), 'existing')
            self.assertFalse((root / '.verification-session').exists())

    def test_missing_command_still_cleans_up(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaises(FileNotFoundError):
                runner.run_session([[str(root / 'missing-program')]], ['reports'], root=root)
            self.assertFalse((root / 'reports').exists())
            self.assertFalse((root / '.verification-session').exists())

    def test_concurrent_session_is_rejected_without_removing_its_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / '.verification-session').mkdir()
            with self.assertRaises(FileExistsError):
                runner.run_session([], ['reports'], root=root)
            self.assertTrue((root / '.verification-session').is_dir())
            self.assertFalse((root / 'reports').exists())


if __name__ == '__main__':
    unittest.main()
