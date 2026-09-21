import json
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class C6ProfileTests(unittest.TestCase):
    def test_machine_readable_profile(self):
        profile = json.loads(
            (ROOT / "configs" / "c6-profile.json").read_text(encoding="utf-8")
        )
        self.assertEqual(profile["profile"], "C6")
        self.assertEqual(profile["max_model_len"], 256000)
        self.assertEqual(
            (profile["prefill"]["dp_size"], profile["prefill"]["tp_size"]),
            (4, 8),
        )
        self.assertEqual(
            (
                profile["decode"]["dp_size"],
                profile["decode"]["dp_size_local"],
                profile["decode"]["tp_size"],
            ),
            (8, 2, 4),
        )
        self.assertEqual(profile["decode"]["max_num_batched_tokens"], 256)
        self.assertTrue(profile["decode"]["mlapo"])
        self.assertFalse(profile["decode"]["fused_mc2"])
        self.assertFalse(profile["decode"]["dynamic_eplb"])

    def test_launch_templates_match_c6(self):
        prefill = (ROOT / "scripts" / "templates" / "prefill.sh").read_text()
        decode = (ROOT / "scripts" / "templates" / "decode.sh").read_text()
        start = (ROOT / "scripts" / "start.sh").read_text()
        self.assertIn('${MAX_MODEL_LEN:-256000}', prefill)
        self.assertIn('${MAX_MODEL_LEN:-256000}', decode)
        self.assertIn('${PREFILL_MAX_NUM_SEQS:-256}', prefill)
        self.assertIn('${DECODE_MAX_NUM_SEQS:-128}', decode)
        self.assertIn('${DECODE_MAX_BATCHED_TOKENS:-256}', decode)
        self.assertIn('${DECODE_DP_SIZE:-8}', start)
        self.assertIn('${DECODE_TP_SIZE:-4}', start)
        self.assertIn('${DECODE_DP_SIZE_LOCAL:-2}', start)
        self.assertIn('enable_mlapo', decode)
        self.assertNotIn('dynamic_eplb', decode.lower())


if __name__ == "__main__":
    unittest.main()
