#!/usr/bin/env python3
"""Render project RTL templates and their canonical file list."""

import argparse
import json
import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined


RTL_SUFFIXES = {".sv", ".svh", ".v", ".vh"}
SV_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")
SUPPORTED_TEST_FRAMEWORKS = {"cocotb"}


def unit_test(
    *,
    module_name: str,
    test_framework: str,
    test_path: str,
    use_wrapper: bool = False,
    rtl_dependencies: list[str] | None = None,
) -> dict[str, object]:
    """Validate and create one unit-test manifest entry."""
    if not isinstance(module_name, str) or not SV_IDENTIFIER.fullmatch(module_name):
        raise ValueError("unit_test.module_name must be a SystemVerilog identifier")
    if (
        not isinstance(test_framework, str)
        or test_framework not in SUPPORTED_TEST_FRAMEWORKS
    ):
        supported = ", ".join(sorted(SUPPORTED_TEST_FRAMEWORKS))
        raise ValueError(
            f"unit_test.test_framework must be one of: {supported}"
        )
    if not isinstance(test_path, str) or not test_path.strip():
        raise ValueError("unit_test.test_path must be a non-empty string")
    if not isinstance(use_wrapper, bool):
        raise ValueError("unit_test.use_wrapper must be true or false")
    if rtl_dependencies is None:
        rtl_dependencies = []
    if not isinstance(rtl_dependencies, list) or not all(
        isinstance(path, str) and path.strip() for path in rtl_dependencies
    ):
        raise ValueError(
            "unit_test.rtl_dependencies must be a list of non-empty paths"
        )

    return {
        "module_name": module_name,
        "test_framework": test_framework,
        "test_path": test_path,
        "use_wrapper": use_wrapper,
        "rtl_dependencies": rtl_dependencies,
    }


def render_tree(
    source_dir: Path,
    output_dir: Path,
    config_path: Path,
    unit_test_manifest: Path | None = None,
) -> None:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("the top level of config.json must be a JSON object")
    registered_unit_tests: list[dict[str, object]] = []
    registered_modules: set[str] = set()

    def register_unit_test(**kwargs: object) -> None:
        entry = unit_test(**kwargs)
        module_name = str(entry["module_name"])
        if module_name in registered_modules:
            raise ValueError(
                f"unit test for module {module_name} is registered more than once"
            )
        registered_modules.add(module_name)
        registered_unit_tests.append(entry)

    environment = Environment(
        loader=FileSystemLoader(source_dir),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
        extensions=["jinja2.ext.do"],
    )
    environment.globals["unit_test"] = register_unit_test

    for source_path in sorted(path for path in source_dir.rglob("*") if path.is_file()):
        relative_path = source_path.relative_to(source_dir)
        output_path = output_dir / relative_path

        if source_path.suffix in RTL_SUFFIXES:
            rendered = environment.get_template(relative_path.as_posix()).render(**config)
        elif source_path.suffix == ".flist":
            rendered = re.sub(
                r"(?m)^(\s*)rtl/",
                r"\1build/rtl/",
                source_path.read_text(encoding="utf-8"),
            )
        else:
            continue

        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered, encoding="utf-8")
        print(f"Rendered {relative_path} -> {output_path}")

    if unit_test_manifest is None:
        unit_test_manifest = output_dir.parent / ".unit-test.json"
    unit_test_manifest.parent.mkdir(parents=True, exist_ok=True)
    unit_test_manifest.write_text(
        json.dumps(registered_unit_tests, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote unit-test manifest -> {unit_test_manifest}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path("rtl"))
    parser.add_argument("--output-dir", type=Path, default=Path("build/rtl"))
    parser.add_argument("--config", type=Path, default=Path("rtl/config.json"))
    parser.add_argument("--unit-test-manifest", type=Path)
    args = parser.parse_args()
    render_tree(
        args.source_dir.resolve(),
        args.output_dir.resolve(),
        args.config.resolve(),
        args.unit_test_manifest.resolve() if args.unit_test_manifest else None,
    )


if __name__ == "__main__":
    main()
