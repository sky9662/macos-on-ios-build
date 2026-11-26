import unittest
from dataclasses import fields, replace
from jit_readiness import Readiness

class TestReadiness(unittest.TestCase):
    def test_every_gate_required(self):
        ready = Readiness(**{f.name: True for f in fields(Readiness)})
        self.assertIsNone(ready.blocker())
        for f in fields(Readiness):
            self.assertIsNotNone(replace(ready, **{f.name: False}).blocker())
    def test_attachment_not_execution(self):
        self.assertEqual(Readiness(True, True, True, True).blocker(),
                         "allocator compatibility unverified")

if __name__ == "__main__":
    unittest.main()
