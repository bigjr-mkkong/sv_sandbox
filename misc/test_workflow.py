"""Small regression checks for the reusable renderer and unit-test runner."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from jinja2 import UndefinedError
from rtl_renderer import render_tree


spec = importlib.util.spec_from_file_location(
    "unit_runner", Path(__file__).with_name("unit-test.py"),
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class WorkflowTest(unittest.TestCase):
    def test_conditional_registration_and_arbitrary_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "rtl"
            source.mkdir()
            config = source / "config.json"
            config.write_text(json.dumps({"enabled": True, "unused_typo": 42}))
            template = source / "dut.sv"
            template.write_text(
                '{% if enabled %}{% do unit_test(module_name="dut", '
                'test_framework="cocotb", test_path="tb.py", '
                'use_wrapper=true, rtl_dependencies=["helper.sv"]) %}'
                'module dut; endmodule{% endif %}'
            )
            output = root / "build" / "rtl"
            manifest = output.parent / ".unit-test.json"
            render_tree(source, output, config)
            entry, = runner.load_manifest(manifest)
            self.assertTrue(entry["use_wrapper"])
            self.assertEqual(entry["rtl_dependencies"], ["helper.sv"])
            self.assertEqual(runner.index_rendered_modules(output), {
                "dut": [output / "dut.sv"],
            })
            config.write_text('{"enabled": false}')
            render_tree(source, output, config)
            self.assertEqual(runner.load_manifest(manifest), [])
            template.write_text("{{ missing_field }}")
            with self.assertRaises(UndefinedError):
                render_tree(source, output, config)

    def test_common_sources_and_all_wrappers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rtl = root / "build" / "rtl"
            rtl.mkdir(parents=True)
            wrappers = root / "dv" / "cocotb_wrappers"
            wrappers.mkdir(parents=True)
            sources = [rtl / "pkg.sv", rtl / "dut.sv"]
            wrapper_sources = [wrappers / "first.sv", wrappers / "second.sv"]
            for path in [*sources, *wrapper_sources, root / "tb.py"]:
                path.touch()
            filelist = root / "rtl.flist"
            filelist.write_text("rtl/pkg.sv // ordered package\nrtl/dut.sv\n")
            common = runner.load_rtl_filelist(root, rtl, filelist)
            self.assertEqual(common, sources)
            with patch.object(runner.subprocess, "run") as run:
                run.return_value.returncode = 7
                result = runner.run_cocotb_test(
                    project_root=root, makefile=root / "Makefile.cocotb",
                    manifest_path=root / "manifest.json", source_path=sources[1],
                    dependency_paths=[], common_sources=common,
                    module_name="dut", test_path="tb.py", use_wrapper=True,
                    simulator="verilator", build_root=root / "build" / "unit-test",
                )
            self.assertEqual(result, 7)
            command = run.call_args.args[0]
            self.assertIn("COCOTB_TOPLEVEL=dut_unit_test", command)
            self.assertIn("VERILOG_SOURCES=" + " ".join(map(str, [
                *sources, *wrapper_sources,
            ])), command)


if __name__ == "__main__":
    unittest.main()
