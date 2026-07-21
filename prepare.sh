#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_bin="${PYTHON:-$project_root/venv/bin/python3}"

if [[ ! -x "$python_bin" ]]; then
    python_bin="$(command -v python3)"
fi

"$python_bin" "$project_root/misc/rtl_renderer.py" \
    --source-dir "$project_root/rtl" \
    --output-dir "$project_root/build/rtl" \
    --config "$project_root/rtl/config.json"
