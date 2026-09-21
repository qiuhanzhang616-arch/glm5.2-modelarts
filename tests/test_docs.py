import re
from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class DocumentationTests(unittest.TestCase):
    def test_relative_links_exist(self):
        missing = []
        for document in ROOT.rglob("*.md"):
            text = document.read_text(encoding="utf-8")
            for target in re.findall(r"\[[^]]*\]\(([^)]+)\)", text):
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                target = target.split("#", 1)[0]
                if target and not (document.parent / target).resolve().exists():
                    missing.append(f"{document.relative_to(ROOT)} -> {target}")
        self.assertEqual(missing, [])

    def test_no_private_environment_markers(self):
        forbidden = (
            "data" + "prev",
            "200." + "152.",
            "192." + "168.",
            "1edd" + "d9c9",
            "6e41" + "cdd0",
        )
        hits = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or ".git" in path.parts or path.suffix == ".pyc":
                continue
            text = path.read_text(encoding="utf-8", errors="ignore").lower()
            for marker in forbidden:
                if marker in text:
                    hits.append(f"{path.relative_to(ROOT)}: {marker}")
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main()
