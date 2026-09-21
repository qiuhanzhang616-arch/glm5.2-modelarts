import importlib.util
from pathlib import Path
import time
import unittest


path = Path(__file__).parents[1] / "scripts" / "topology.py"
spec = importlib.util.spec_from_file_location("topology", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class TopologyTests(unittest.TestCase):
    def records(self):
        now = time.time()
        roles = ["P_ENTRY"] + ["P_WORKER"] * 3 + ["D_WORKER"] * 4
        return now, [
            {
                "hostname": f"node-{index}",
                "cohort": "run1",
                "role": role,
                "ip": f"10.0.0.{index + 1}",
                "devices": list(range(8)),
                "timestamp": now,
            }
            for index, role in enumerate(roles)
        ]

    def test_entry_and_decode_positions(self):
        now, records = self.records()
        entry = module.select(records, "run1", "node-0", "10.0.0.1", "P_ENTRY", now)
        decode = module.select(records, "run1", "node-6", "10.0.0.7", "D_WORKER", now)
        self.assertEqual((entry["side"], entry["position"]), ("P", 0))
        self.assertEqual((decode["side"], decode["position"]), ("D", 2))
        self.assertEqual(entry["p_master"], "10.0.0.1")
        self.assertEqual(entry["d_master"], "10.0.0.5")

    def test_duplicate_ip_is_rejected(self):
        now, records = self.records()
        records[-1]["ip"] = records[-2]["ip"]
        with self.assertRaises(ValueError):
            module.select(records, "run1", "node-0", "10.0.0.1", "P_ENTRY", now)


if __name__ == "__main__":
    unittest.main()
