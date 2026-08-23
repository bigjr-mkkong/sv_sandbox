#!/usr/bin/env python3
"""Run every RTL unit test registered in build/.unit-test.json."""

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path


RTL_SUFFIXES = {".sv", ".v"}
MODULE_DECLARATION = re.compile(
    r"(?m)^\s*module\s+(?:automatic\s+)?([A-Za-z_][A-Za-z0-9_$]*)\b"
)
SV_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")


class UnitTestError(RuntimeError):
    """Report invalid unit-test metadata or an unusable test setup."""


def project_path(project_root: Path, path: Path) -> Path:
    """Resolve a command-line path relative to the project root."""
    return path.resolve() if path.is_absolute() else (project_root / path).resolve()


def load_manifest(manifest_path: Path) -> list[dict[str, object]]:
    """Load and validate the renderer-generated unit-test manifest."""
    if not manifest_path.is_file():
        raise UnitTestError(
            f"unit-test manifest not found: {manifest_path}; run make prepare first"
        )

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise UnitTestError(f"invalid JSON in {manifest_path}: {error}") from error

    if not isinstance(manifest, list):
        raise UnitTestError("unit-test manifest must contain a JSON list")

    entries: list[dict[str, object]] = []
    seen_modules: set[str] = set()
    required_fields = {
        "module_name",
        "test_framework",
        "test_path",
        "use_wrapper",
    }
    for index, raw_entry in enumerate(manifest):
        if not isinstance(raw_entry, dict):
            raise UnitTestError(f"unit-test entry {index} must be a JSON object")
        missing_fields = required_fields - raw_entry.keys()
        if missing_fields:
            missing = ", ".join(sorted(missing_fields))
            raise UnitTestError(f"unit-test entry {index} is missing: {missing}")

        entry = {field: raw_entry[field] for field in required_fields}
        rtl_dependencies = raw_entry.get("rtl_dependencies", [])
        string_fields = ("module_name", "test_framework", "test_path")
        if not all(isinstance(entry[field], str) for field in string_fields):
            raise UnitTestError(
                f"module_name, test_framework, and test_path in unit-test entry "
                f"{index} must be strings"
            )
        if not isinstance(entry["use_wrapper"], bool):
            raise UnitTestError(
                f"use_wrapper in unit-test entry {index} must be true or false"
            )
        if not isinstance(rtl_dependencies, list) or not all(
            isinstance(path, str) and path.strip() for path in rtl_dependencies
        ):
            raise UnitTestError(
                f"rtl_dependencies in unit-test entry {index} must be a list "
                "of non-empty paths"
            )
        entry["rtl_dependencies"] = rtl_dependencies
        module_name = str(entry["module_name"])
        if not SV_IDENTIFIER.fullmatch(module_name):
            raise UnitTestError(
                f"invalid SystemVerilog module name in entry {index}: {module_name}"
            )
        if module_name in seen_modules:
            raise UnitTestError(f"duplicate unit-test module: {module_name}")
        seen_modules.add(module_name)
        entries.append(entry)

    return entries


def index_rendered_modules(rtl_dir: Path) -> dict[str, list[Path]]:
    """Map module declarations to the rendered files containing them."""
    if not rtl_dir.is_dir():
        raise UnitTestError(f"rendered RTL directory not found: {rtl_dir}")

    module_sources: dict[str, list[Path]] = {}
    for source_path in sorted(path for path in rtl_dir.rglob("*") if path.is_file()):
        if source_path.suffix not in RTL_SUFFIXES:
            continue
        source = source_path.read_text(encoding="utf-8")
        for module_name in MODULE_DECLARATION.findall(source):
            module_sources.setdefault(module_name, []).append(source_path)
    return module_sources


def find_module_source(
    module_sources: dict[str, list[Path]], module_name: str
) -> Path:
    """Return the unique rendered source defining a registered module."""
    matches = module_sources.get(module_name, [])
    if not matches:
        raise UnitTestError(
            f"could not find module {module_name} in the rendered RTL tree"
        )
    if len(matches) > 1:
        paths = ", ".join(str(path) for path in matches)
        raise UnitTestError(f"module {module_name} is defined more than once: {paths}")
    return matches[0]


def cocotb_test_module(project_root: Path, test_path: str) -> tuple[str, Path]:
    """Convert a Python file or dotted path into a cocotb import module."""
    requested_path = Path(test_path)
    candidate = project_path(project_root, requested_path)

    if requested_path.suffix == ".py":
        try:
            relative_path = candidate.relative_to(project_root)
        except ValueError as error:
            raise UnitTestError(
                f"cocotb test must be inside the project: {candidate}"
            ) from error
        module_name = ".".join(relative_path.with_suffix("").parts)
        test_file = candidate
    else:
        module_name = test_path.strip().replace("\\", ".").replace("/", ".")
        module_name = module_name.strip(".")
        test_file = project_root.joinpath(*module_name.split(".")).with_suffix(".py")

    if not module_name:
        raise UnitTestError("cocotb test_path must not be empty")
    if not test_file.is_file():
        raise UnitTestError(f"cocotb test file not found: {test_file}")
    return module_name, test_file


def run_cocotb_test(
    *,
    project_root: Path,
    makefile: Path,
    manifest_path: Path,
    source_path: Path,
    dependency_paths: list[Path],
    common_sources: list[Path],
    module_name: str,
    test_path: str,
    use_wrapper: bool,
    simulator: str,
    build_root: Path,
) -> int:
    """Invoke the existing cocotb make flow for one registered module."""
    test_module, test_file = cocotb_test_module(project_root, test_path)
    top_module = module_name
    source_paths = list(
        dict.fromkeys([*common_sources, *dependency_paths, source_path])
    )
    compile_dependencies = [test_file, manifest_path, *dependency_paths]
    if use_wrapper:
        wrapper_dir = project_root / "dv" / "cocotb_wrappers"
        if not wrapper_dir.is_dir():
            raise UnitTestError(f"cocotb wrapper directory not found: {wrapper_dir}")
        wrapper_paths = sorted(
            path
            for path in wrapper_dir.rglob("*")
            if path.is_file() and path.suffix in RTL_SUFFIXES
        )
        if not wrapper_paths:
            raise UnitTestError(
                f"no RTL sources found in cocotb wrapper directory: {wrapper_dir}"
            )
        top_module = f"{module_name}_unit_test"
        source_paths.extend(wrapper_paths)
        compile_dependencies.extend(wrapper_paths)

    safe_module_name = re.sub(r"[^A-Za-z0-9_.-]", "_", module_name)
    sim_build = build_root / safe_module_name
    results_file = sim_build / "results.xml"
    trace_file = sim_build / "dump.vcd"

    command = [
        "make",
        "-f",
        str(makefile),
        f"SIM={simulator}",
        f"SIM_BUILD={sim_build}",
        f"COCOTB_RESULTS_FILE={results_file}",
        "CUSTOM_COMPILE_DEPS="
        + " ".join(str(path) for path in compile_dependencies),
        f"USER_SIM_ARGS=--trace-file {trace_file}",
        "VERILOG_SOURCES=" + " ".join(str(path) for path in source_paths),
        f"COCOTB_TOPLEVEL={top_module}",
        f"COCOTB_TEST_MODULES={test_module}",
    ]

    print(f"\n[unit-test] {module_name} ({test_module})", flush=True)
    print(f"[unit-test] {shlex.join(command)}", flush=True)
    completed = subprocess.run(command, cwd=project_root, check=False)
    return completed.returncode


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path("build/.unit-test.json"))
    parser.add_argument("--rtl-dir", type=Path, default=Path("build/rtl"))
    parser.add_argument("--build-dir", type=Path, default=Path("build/unit-test"))
    parser.add_argument("--cocotb-makefile", type=Path, default=Path("Makefile.cocotb"))
    parser.add_argument("--sim", default="verilator")
    args = parser.parse_args()

    manifest_path = project_path(project_root, args.manifest)
    rtl_dir = project_path(project_root, args.rtl_dir)
    build_root = project_path(project_root, args.build_dir)
    makefile = project_path(project_root, args.cocotb_makefile)

    try:
        entries = load_manifest(manifest_path)
        if not entries:
            print("No RTL unit tests are registered.")
            return 0
        module_sources = index_rendered_modules(rtl_dir)
        common_sources = [
            path
            for path in [
                project_root
                / "third_party"
                / "taxi"
                / "src"
                / "axi"
                / "rtl"
                / "taxi_axil_if.sv",
                rtl_dir / "config_pkg.sv",
            ]
            if path.is_file()
        ]
    except UnitTestError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    failures: list[str] = []
    for entry in entries:
        module_name = str(entry["module_name"])
        framework = str(entry["test_framework"])
        try:
            source_path = find_module_source(module_sources, module_name)
            dependency_paths = []
            for dependency in entry["rtl_dependencies"]:
                relative_dependency = Path(str(dependency))
                if relative_dependency.parts[:1] == ("rtl",):
                    relative_dependency = Path(*relative_dependency.parts[1:])
                dependency_path = (rtl_dir / relative_dependency).resolve()
                try:
                    dependency_path.relative_to(rtl_dir)
                except ValueError as error:
                    raise UnitTestError(
                        f"RTL dependency escapes rendered tree: {dependency}"
                    ) from error
                if not dependency_path.is_file():
                    raise UnitTestError(
                        f"RTL dependency not found for {module_name}: "
                        f"{dependency_path}"
                    )
                dependency_paths.append(dependency_path)
            if framework != "cocotb":
                raise UnitTestError(
                    f"unsupported test framework for {module_name}: {framework}"
                )
            return_code = run_cocotb_test(
                project_root=project_root,
                makefile=makefile,
                manifest_path=manifest_path,
                source_path=source_path,
                dependency_paths=dependency_paths,
                common_sources=[
                    path for path in common_sources if path != source_path
                ],
                module_name=module_name,
                test_path=str(entry["test_path"]),
                use_wrapper=bool(entry["use_wrapper"]),
                simulator=args.sim,
                build_root=build_root,
            )
            if return_code:
                failures.append(module_name)
        except UnitTestError as error:
            print(f"error: {error}", file=sys.stderr)
            failures.append(module_name)

    if failures:
        print(f"\nUnit tests failed: {', '.join(failures)}", file=sys.stderr)
        return 1

    print(f"\nAll {len(entries)} RTL unit test(s) passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
