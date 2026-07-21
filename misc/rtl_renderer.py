#!/usr/bin/env python3
"""Render project RTL templates and their canonical file list."""

import argparse
import json
import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined


RTL_SUFFIXES = {".sv", ".svh", ".v", ".vh"}
SV_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")


def validate_config(config: object) -> dict:
    """Validate common module switches and this template's UART settings."""
    if not isinstance(config, dict):
        raise ValueError("the top level of config.json must be a JSON object")

    for instance_name, module_config in config.items():
        if not isinstance(module_config, dict):
            raise ValueError(f"{instance_name} must be a JSON object")
        if not isinstance(module_config.get("ENABLE"), bool):
            raise ValueError(f"{instance_name}.ENABLE must be true or false")

        module_name = module_config.get("module_name")
        if not isinstance(module_name, str) or not SV_IDENTIFIER.fullmatch(module_name):
            raise ValueError(
                f"{instance_name}.module_name must be a SystemVerilog identifier"
            )

    if "UART0" not in config:
        raise ValueError("config.json must contain a UART0 object")

    uart_config = config["UART0"]
    if "Fclk" in uart_config:
        raise ValueError(
            "UART0.Fclk is project-owned; configure "
            "config_pkg::CLOCK_FREQUENCY_HZ instead"
        )
    if uart_config["ENABLE"]:
        for field_name in ("AXI_DATAW", "PRE_W", "BAUD"):
            value = uart_config.get(field_name)
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                raise ValueError(
                    f"UART0.{field_name} must be a positive integer when UART0 is enabled"
                )

    return config


def render_tree(source_dir: Path, output_dir: Path, config_path: Path) -> None:
    config = validate_config(json.loads(config_path.read_text(encoding="utf-8")))
    environment = Environment(
        loader=FileSystemLoader(source_dir),
        undefined=StrictUndefined,
        keep_trailing_newline=True,
    )

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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path("rtl"))
    parser.add_argument("--output-dir", type=Path, default=Path("build/rtl"))
    parser.add_argument("--config", type=Path, default=Path("rtl/config.json"))
    args = parser.parse_args()
    render_tree(args.source_dir.resolve(), args.output_dir.resolve(), args.config.resolve())


if __name__ == "__main__":
    main()
