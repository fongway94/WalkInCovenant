#!/usr/bin/env python3
"""The pinned Godot reference must work with a cold cache and no network."""
import contextlib
import io
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import api_check  # noqa: E402
import xref_check  # noqa: E402


class OfflineGodotReference(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.old_cache, self.old_gh = api_check.CACHE, api_check.gh
        self.fetches = []
        api_check.CACHE = self.directory.name
        api_check.gh = lambda path: self.fetches.append(path) or None
        api_check.REF = None
        api_check.docs.clear()
        api_check.findings.clear()
        xref_check.findings.clear()
        xref_check._engine_cache.clear()

    def tearDown(self):
        api_check.CACHE, api_check.gh = self.old_cache, self.old_gh
        api_check.docs.clear()
        api_check.findings.clear()
        xref_check.findings.clear()
        xref_check._engine_cache.clear()
        self.directory.cleanup()

    def test_project_cross_references_need_no_network_or_warm_cache(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = xref_check.main()
        self.assertEqual(status, 0, output.getvalue())
        self.assertNotIn("skipped", output.getvalue())
        self.assertEqual(self.fetches, [], "an engine class was missing from the pinned reference")

    def test_project_engine_api_is_checked_offline(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = api_check.main()
        self.assertEqual(status, 0, output.getvalue())
        self.assertNotIn("skipped", output.getvalue())
        self.assertGreaterEqual(sum(doc is not None for doc in api_check.docs.values()), 50)

    def test_first_cross_reference_can_be_an_inherited_engine_member(self):
        # Filesystem traversal order differs across machines. If the first
        # lookup is an inherited member rather than an engine type annotation,
        # the reference version must already be initialized before fetch_doc().
        root = pathlib.Path(self.directory.name)
        (root / "project.godot").write_text("[autoload]\n", encoding="utf-8")
        (root / "probe.gd").write_text(
            "class_name OrderedProbe\n"
            "extends Node\n"
            "func probe():\n"
            "\tvar actor: OrderedProbe = OrderedProbe.new()\n"
            "\tactor.queue_free()\n"
            "\tvar layer: CanvasLayer = CanvasLayer.new()\n"
            "\tlayer.visible = true\n",
            encoding="utf-8",
        )
        old_root = xref_check.ROOT
        output = io.StringIO()
        try:
            xref_check.ROOT = str(root)
            with contextlib.redirect_stdout(output):
                status = xref_check.main()
        finally:
            xref_check.ROOT = old_root
        self.assertEqual(status, 0, output.getvalue())
        self.assertNotIn("skipped", output.getvalue())
        self.assertEqual(self.fetches, [], "the first inherited lookup must use the pinned reference")

    def test_offline_cross_reference_still_rejects_an_unknown_class(self):
        root = pathlib.Path(self.directory.name)
        (root / "project.godot").write_text("[autoload]\n", encoding="utf-8")
        (root / "probe.gd").write_text(
            "class_name ReferenceProbe\n"
            "extends Node2D\n"
            "func probe():\n"
            "\tvar good: CharacterBody2D = CharacterBody2D.new()\n"
            "\tgood.position = Vector2.ZERO\n"
            "\tvar missing: NotARealProjectClass\n"
            "\tmissing.some_method()\n",
            encoding="utf-8",
        )
        old_root = xref_check.ROOT
        output = io.StringIO()
        try:
            xref_check.ROOT = str(root)
            with contextlib.redirect_stdout(output):
                status = xref_check.main()
        finally:
            xref_check.ROOT = old_root
        self.assertEqual(status, 1, output.getvalue())
        self.assertIn("NO-CLASS", output.getvalue())
        self.assertIn("NotARealProjectClass", output.getvalue())

    def test_offline_api_still_catches_a_real_member_typo(self):
        api_check.REF = api_check.godot_version()
        api_check.SKIP_TYPES = set()
        api_check.own_classes = set()
        script = pathlib.Path(self.directory.name) / "bad_member.gd"
        script.write_text(
            "extends Node2D\n"
            "func probe():\n"
            "\tvar body: CharacterBody2D = CharacterBody2D.new()\n"
            "\tbody.position = Vector2.ZERO\n"
            "\tbody.this_member_does_not_exist = 1\n",
            encoding="utf-8",
        )
        api_check.scan(str(script))
        findings = [(rule, message) for _, _, rule, message in api_check.findings]
        self.assertTrue(any(rule == "NO-MEMBER" and "this_member_does_not_exist" in message
                            for rule, message in findings), findings)
        self.assertFalse(any("body is a CharacterBody2D and has no 'position'" in message
                             for _, message in findings), findings)
        self.assertEqual(self.fetches, [], "the inheritance chain should be available offline")


if __name__ == "__main__":
    unittest.main()
