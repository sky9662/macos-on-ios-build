import pathlib
import tempfile
import unittest
from unittest.mock import patch

from tc_jit_audit import audit, summarize, mode_summary, control_flow_summary, BINARIES

# Synthetic text representing objdump output; no commercial instructions or binaries.
FIXTURE = """
(__TEXT,__text) section
_c_get_memory:
    1000: 00 00 00 00 bl 0x2000 ; symbol stub for: _mmap
_c_set_protection:
    1010: 00 00 00 00 bl 0x2004 ; symbol stub for: _pthread_jit_write_protect_np
    1014: 00 00 00 00 b 0x2008 ; symbol stub for: _sys_icache_invalidate
_c_jit:
    1018: 00 00 00 00 br x0
_fixture:
    1020: 00 00 00 00 bl _c_get_memory
    1024: 00 00 00 00 bl _c_set_protection
    1028: 00 00 00 00 b _c_jit
    102c: 00 00 00 00 blr x0
"""


class AuditTests(unittest.TestCase):
    def test_named_calls_and_tail_branches(self):
        report = summarize(FIXTURE)
        self.assertEqual(report["direct_calls"]["_c_get_memory"], 1)
        self.assertEqual(report["direct_calls"]["_c_set_protection"], 1)
        self.assertEqual(report["direct_calls"]["_c_jit"], 1)
        self.assertEqual(report["wrapper_calls"]["_c_set_protection"]["_sys_icache_invalidate"], 1)
        self.assertEqual(report["wrapper_calls"]["_c_set_protection"]["_pthread_jit_write_protect_np"], 1)

    def test_control_flow_inventory(self):
        result = control_flow_summary(FIXTURE)
        self.assertEqual(result["wrappers"]["_c_jit"]["indirect_transfers"], 1)
        self.assertEqual(result["wrappers"]["_c_set_protection"]["named_api_sequence"],
                         ["_pthread_jit_write_protect_np", "_sys_icache_invalidate"])
        self.assertEqual(result["direct_caller_patterns"], [
            {"entry_points": ["_c_get_memory", "_c_jit", "_c_set_protection"], "function_count": 1}])
        self.assertNotIn("_fixture", str(result))
        self.assertNotIn("1018", str(result))

    def test_control_flow_instruction_formats(self):
        result = control_flow_summary("_c_jit:\n 1000: d63f0000 blr x0\n 1004: stp x1, x2, [sp]\n 1008: ret\n(__DATA,__data) section\n 1010: br x0\n")
        self.assertEqual(result["wrappers"]["_c_jit"]["indirect_transfers"], 1)
        self.assertEqual(result["wrappers"]["_c_jit"]["store_instructions"], 1)
        self.assertEqual(result["wrappers"]["_c_jit"]["returns"], 1)

    def test_flags_are_exact_and_not_claimed_as_supported(self):
        raw = bytes([0]).join([b"@--no-ui", b"@--no-draw", b"--no-jit-extra", b"some--interpreter", b"--disable-jit", b""])
        self.assertEqual(raw.count(bytes([0])), 5)
        syms = "0000000100000000 l F __TEXT,__text _jit__modelZsimulationZjitZjit_u1\n0000000100000004 l F __TEXT,__text _interpreter_fixture"
        result = mode_summary(raw, syms)
        self.assertEqual(result["known_flag_strings"], ["--disable-jit", "--no-draw", "--no-ui"])
        self.assertEqual(result["possible_interpreter_symbol_count"], 1)
        self.assertEqual(result["simulation_jit_symbol_count"], 1)
        self.assertIn("No proof", result["limit"])

    def test_empty_inventory_is_not_an_execution_pass(self):
        report = mode_summary(b"not an option", "")
        self.assertEqual(report["known_flag_strings"], [])
        self.assertEqual(report["symbol_records_inspected"], 0)
        self.assertIn("No proof", report["limit"])

    def test_missing_symbols_not_a_pass(self):
        self.assertEqual(summarize("no symbols")["definitions"], [])
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name in BINARIES:
                (root / name).write_bytes(b"synthetic")
            with patch("tc_jit_audit.subprocess.check_output", return_value="no symbols"):
                with self.assertRaises(ValueError):
                    audit(root, "fixture-objdump")

    def test_reports_both_and_never_claims_launch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name in BINARIES:
                (root / name).write_bytes(b"synthetic")
            with patch("tc_jit_audit.subprocess.check_output", return_value=FIXTURE):
                report = audit(root, "fixture-objdump")
            self.assertEqual(tuple(report["binaries"]), BINARIES)
            self.assertFalse(report["runtime_verified"])
            self.assertFalse(report["game_launch_authorized"])
            for name in BINARIES:
                self.assertEqual((root / name).read_bytes(), b"synthetic")


if __name__ == "__main__":
    unittest.main()
