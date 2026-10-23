# TOGAWA CPU / SystemVerilog simulation template

This repository develops an unfinished TOGAWA CPU using a SystemVerilog and
cocotb template. It includes RTL rendering, unit tests, waveform traces, coverage,
and optional synthesis and FPGA flows.

The CPU components are tested individually. The current `top_module` still runs
the template's UART example, transmitting `A` through `Z` at 115200 baud. The
FPGA and OpenROAD targets therefore build that example, not a complete CPU.

## Installation and prerequisites

The instructions below use Ubuntu 22.04/24.04, either directly or inside WSL 2.
You need internet access to download the tools, Python packages, and Git
submodules. Simulation does not require an FPGA, Vivado, or Docker.

### 1. Prepare the operating system

On Windows, first install Ubuntu in WSL from an administrator PowerShell:

```powershell
wsl --install -d Ubuntu
```

Restart if prompted, launch Ubuntu, and create its Linux user account. Run the
remaining commands in the Ubuntu terminal. Keep the checkout in your Linux home
directory, for example `~/projects/`, to avoid building across the Windows
filesystem. See Microsoft's [WSL installation guide](https://learn.microsoft.com/en-us/windows/wsl/install).

On Ubuntu, install the host tools:

```bash
sudo apt update
sudo apt install -y git build-essential perl python3 python3-venv \
    python3-pip python3-dev ca-certificates curl

python3 --version
make --version
g++ --version
```

The project requires Python **3.10 or later**, GNU Make **4.3 or later**, Bash,
and a compiler supporting **C++17**. The Ubuntu versions above provide suitable
host tools. Verilator compiles simulations into native executables, so a C++
compiler is needed even when you only edit SystemVerilog or Python.

`python3-dev` supplies development files for the distribution's Python.
cocotb also needs a matching shared `libpython`; this matters if you choose a
custom Python installation. This project installs its pinned Python dependencies
into a virtual environment rather than system Python.

### 2. Install OSS CAD Suite

[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build#installation) is a
prebuilt collection of HDL tools. Download a dated archive from its
[releases page](https://github.com/YosysHQ/oss-cad-suite-build/releases); you do
not need to build Yosys or Verilator from source.

The current development installation reports suite version `20260308`.
The [2026-03-08 release](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-03-08)
is a starting point for matching that environment. If choosing a newer release,
agree on the same date with your collaborator and rerun the checks below.

Choose the archive matching the machine where the commands will run:

| Machine | Archive platform |
| --- | --- |
| Linux or WSL on an Intel/AMD 64-bit machine | `linux-x64` |
| Linux on a 64-bit ARM machine | `linux-arm64` |

Extract it into a user-owned directory. In this example, replace `YYYYMMDD`
with the date in your downloaded filename, and adjust the download path or
platform if necessary:

```bash
mkdir -p "$HOME/tools"
tar -xzf "$HOME/Downloads/oss-cad-suite-linux-x64-YYYYMMDD.tgz" \
    -C "$HOME/tools"
export OSS_CAD_SUITE="$HOME/tools/oss-cad-suite"

"$OSS_CAD_SUITE/bin/verilator" --version
"$OSS_CAD_SUITE/bin/yosys" -V
"$OSS_CAD_SUITE/bin/yosys" -m slang -Q -p 'help read_slang'
```

The last command checks the Slang plugin used to read this project's
SystemVerilog. Keep collaborators on the same dated suite release; record the
archive name when reporting tool-dependent failures.

Repeat the `export OSS_CAD_SUITE=...` command in each new terminal, or add it to
`~/.bashrc` (or your shell's startup file). Alternatively, pass
`OSS_CAD_SUITE=/absolute/path/to/oss-cad-suite` to each `make` command. A suite
installed at `/opt/oss-cad-suite` is detected automatically without an override.

The Makefile adds the selected suite's tools to its own environment. You do not
need to source the suite's `environment` script or manually activate Python
before using `make`. If you want to run tools such as GTKWave directly, use:

```bash
export PATH="$OSS_CAD_SUITE/bin:$PATH"
```

For other operating systems, follow the suite's upstream installation
instructions and provide GNU Make and Bash. The commands in this README use the
Linux workflow; native Windows setup is outside this guide.

### 3. Clone the project and its submodules

Replace `<repository-url>` with the shared repository or your fork's URL:

```bash
mkdir -p "$HOME/projects"
cd "$HOME/projects"
git clone --recurse-submodules <repository-url> sv_sandbox
cd sv_sandbox
```

For an existing checkout, initialize any missing submodules:

```bash
git submodule update --init --recursive
```

The submodules contain [BaseJump STL](https://github.com/bespoke-silicon-group/basejump_stl)
and [Taxi](https://github.com/fpganinja/taxi). Keep the revisions recorded by the
repository; there is no need to update them to their latest upstream versions.

### 4. Install the project's Python packages

From the repository root, select Ubuntu's Python explicitly:

```bash
make setup VENV_PYTHON=/usr/bin/python3
venv/bin/python3 --version
venv/bin/cocotb-config --version
make doctor
```

`make setup` creates `venv/` and installs [requirements.txt](requirements.txt),
including cocotb 2.0.1, Jinja2, and pyserial. Rerun it when those requirements
change. Without `VENV_PYTHON`, the Makefile prefers a Python selected by pyenv
and otherwise uses `python3`.

The virtual environment takes precedence over the suite's bundled Python tools.
Do not replace the pinned cocotb with a different system installation. Upstream
[cocotb installation documentation](https://docs.cocotb.org/en/v2.0.1/install.html)
has more information about Python and `libpython` requirements.

`make doctor` should print `Toolchain and submodules are ready.` It checks the
simulator, Python dependencies, Yosys/Slang, and iCE40 tools. Coverage also uses
`verilator_coverage`, supplied by OSS CAD Suite.

### 5. Run the first checks

Keep `RENDER_OPTION.SYNTH` set to `false` in [rtl/config.json](rtl/config.json),
then run:

```bash
make lint
make unit-test
make test
```

- `make lint` renders and lints the current top-level source set.
- `make unit-test` runs the registered CPU, IRAM, SPI-arbiter, and
  alphabet-generator tests, then generates annotated Verilator coverage.
- `make test` runs the SystemVerilog UART testbench and C++ ideal-memory checks.

These commands are a useful first check of a collaborator's environment. They
verify different parts of the project; UART success alone does not validate the
CPU components. Running `make` with no target only prints help.

### Troubleshooting setup

| Symptom | What to check |
| --- | --- |
| `verilator` or `yosys` not found | Verify `OSS_CAD_SUITE` names the extracted directory containing `bin/`, not the archive or its parent. Run `make doctor` again. |
| `read_slang` or Slang plugin unavailable | Select a suite containing the Slang plugin; a separate system Yosys installation may not include it. |
| `venv` creation fails or `ensurepip` is missing | Install `python3-venv` matching the selected Python. |
| Missing `jinja2`, `serial`, or `cocotb-config` | Run `make setup` from the repository root and use its `venv/`. |
| cocotb cannot locate `libpython` | Use `/usr/bin/python3` with its matching development package. For pyenv/custom Python, provide a shared-library build; create a fresh venv from that interpreter. |
| Missing Taxi or BSG source files | Run `git submodule update --init --recursive`. |
| GNU Make reports grouped-target syntax errors | Check `make --version`; this Makefile requires GNU Make 4.3+. |
| Simulation reports `SYNTH ON` | Set `RENDER_OPTION.SYNTH=false` before cocotb tests. |
| Old build errors after changing toolchain | Run `make clean`, then repeat setup checks and rebuild. `make clean` removes generated results, coverage, and traces. |

## Current CPU project

TOGAWA is a small 16-bit CPU with two stages, IF and IDEXMEM. TOGA toggles a
working-register bit and conditionally branches. WA writes back a dirty working
word and loads another word; HALT completes pending write-back before stopping.
The implementation and integration are still in progress.

| Component | Source | Current role |
| --- | --- | --- |
| CPU pipeline | [rtl/togawa.sv](rtl/togawa.sv) | Executes TOGA, WA, and HALT; tested using ideal instruction and data memories. |
| SRAM and instruction buffer | [rtl/cache.sv](rtl/cache.sv) | Holds a 16-instruction window and refills it with byte requests. |
| SPI arbiter | [rtl/spi_arbiter.sv](rtl/spi_arbiter.sv) | Shares a downstream memory between two requesters and buffers response pulses. |
| SPI master | [rtl/spi_master.sv](rtl/spi_master.sv) | Production serial-transfer module; unit tests use the shared ideal SPI RAM model. |
| Interfaces and static settings | [rtl/config_pkg.sv](rtl/config_pkg.sv) | Defines the SPI interface, data width, and project clock. |
| Current hardware example | [rtl/top_module.sv](rtl/top_module.sv), [rtl/main_module.sv](rtl/main_module.sv) | Connects the alphabet generator to Taxi UART. |

The CPU, instruction buffer, and arbiter have separate verification wrappers;
they are not yet assembled into a complete CPU top. A complete data-cache RTL
implementation is also pending.

## Development and verification

Run commands from the repository root:

```bash
make prepare             # Render RTL and generate the unit-test manifest
make lint                # Lint the default top-level design
make unit-test           # Run all registered module tests and generate coverage
make compile             # Compile the SystemVerilog UART testbench
make test                # Run that testbench and ideal-memory checks
make test-cocotb          # Run the top-level UART cocotb test
make help                # List available targets
```

`make lint` uses the default top's canonical source list; it does not replace
running the CPU-component tests. Individual unit-test DUTs and their dependencies
are compiled by `make unit-test`.

### Test registration and models

RTL templates register cocotb tests through Jinja's `do` extension:

```jinja
{% do unit_test(
    module_name = "main_module",
    test_framework = "cocotb",
    test_path = "dv/cocotb_benches/main_module_tb.py",
    use_wrapper = true) %}
```

`make prepare` writes these registrations to `build/.unit-test.json` without
executing tests. [misc/unit-test.py](misc/unit-test.py) runs each registered
module in a separate simulation and stops on the first failure.

With `use_wrapper=true`, the top must be `<module_name>_unit_test`. The runner
compiles the files under `dv/cocotb_wrappers/`, including shared simulation
models; it selects only the registered DUT for that run. Optional
`rtl_dependencies=["helper.sv"]` entries add rendered RTL dependencies.

The CPU tests use [cpp/ideal_mem.cpp](cpp/ideal_mem.cpp) through DPI. Each memory
handle has its own configured data width; instruction/data SRAM models use
16 bits and the shared [ideal SPI RAM](dv/cocotb_wrappers/ideal_spi_ram.sv) uses
8 bits. IRAM and arbiter tests exercise memory transactions through this model,
without serial SPI timing or a Python SPI-slave emulator. C++ sources under
`cpp/` are automatically included in the cocotb/Verilator build.

The registered suites cover:

- CPU execution, branches, write-back, and carry/overflow programs.
- IRAM reset, fills, 16- and 64-instruction streams, jumps, boundaries,
  wraparound, response backpressure, and redirects during refill.
- Arbiter contention, response buffering, shared memory, and reset cancellation.
- Alphabet-generator wraparound and backpressure.

### Results, waveforms, and coverage

Each module's output lives under `build/unit-test/<module>/`:

| File | Contents |
| --- | --- |
| `results.xml` | cocotb test results |
| `dump.vcd` | Waveform trace |
| `coverage.dat` | That module's Verilator coverage |

After a successful full run, open `build/unit-test/coverage/index.md` for links
to every annotated source. The raw combined data is
`build/unit-test/coverage/merged.dat`. For example, annotated IRAM/SRAM RTL is:

```text
build/unit-test/coverage/annotated/build/rtl/cache.sv
```

Annotations include line, branch, expression, and toggle coverage. `%000000`
marks an uncovered source line, `-000000` marks an uncovered individual point,
and `~` indicates partial coverage. Evaluate gaps against the module's contract;
coverage alone does not establish correct behavior.

For waveform inspection, launch the suite's GTKWave from the same terminal:

```bash
"$OSS_CAD_SUITE/bin/gtkwave" build/unit-test/iram_blk/dump.vcd
```

If using the default `/opt/oss-cad-suite` installation without the environment
variable, substitute that directory in the command. A graphical viewer needs a
working display; tests and coverage generation can run without one.

## Editing RTL and collaborating

- Edit source files under `rtl/`; generated copies under `build/rtl/` are
  replaced by the renderer. Jinja template syntax is resolved before HDL tools
  read the files, so use the Make targets rather than compiling templates directly.
- [rtl/rtl.flist](rtl/rtl.flist) is the canonical source manifest for the default
  design. Add sources needed by that design there, keeping interfaces/packages
  ahead of their users. Module-level tests may register additional dependencies.
- [rtl/config_pkg.sv](rtl/config_pkg.sv) holds project-owned settings, including
  the 48 MHz clock. [rtl/config.json](rtl/config.json) selects third-party
  integrations such as `UART0.ENABLE`, baud rate, and Taxi parameters.
- Keep `UART0.ENABLE=true` for the supplied UART tests. Disabling it renders an
  idle transmit pin and applies backpressure to the alphabet generator.
- After pulling changes, run `git submodule update --init --recursive` and
  rerun `make setup` if `requirements.txt` changed. Run relevant unit tests before
  sharing an RTL change; include the suite release and failing test name when
  reporting a problem.
- Share source changes and dependency revisions. Generated files under `build/`
  are ignored. Local development notes in `AGENTS.md` are also ignored and are
  not distributed with a normal clone.

## Optional synthesis and hardware flows

These flows currently target the UART example. Start with simulation before
installing optional board-programming or physical-design tools.

### Generic synthesis and FPGA checks

```bash
make synth                   # Generic Yosys/Slang netlist
make test-gls                # Generic post-synthesis UART test
make icebreaker-bitstream    # iCEBreaker synthesis, place-and-route, bitstream
make test-icebreaker-gls      # iCE40-mapped UART test
make check-vivado-sources    # Syntax-check the Basys 3 source set
make check                   # All open-source checks above, plus RTL tests
```

The iCEBreaker flow generates a PLL for the board's 12 MHz input and the
project's 48 MHz clock using `icepll`. Its post-synthesis simulation bypasses the
PLL because the open-source primitive model does not simulate PLL behavior.

To program an attached iCEBreaker:

```bash
make program-icebreaker      # Volatile SRAM programming
make flash-icebreaker        # Nonvolatile flash programming
```

Programming uses openFPGALoader. Configure USB/udev access for your board;
programming is not part of `make check`.

### Basys 3

Install Vivado separately and put `vivado` on `PATH` for implementation:

```bash
make vivado-bitstream
make program-basys3
```

Vivado creates the 48 MHz clock IP and writes its project/bitstream under
`synth/vivado_basys3/build/`. Programming uses openFPGALoader.
After programming either board, monitor UART with:

```bash
venv/bin/python3 read-uart.py --port /dev/ttyUSB0 --baud 115200
```

Adjust the device path for your system.

### OpenROAD

Install Docker, obtain an ORFS image, and clone
[OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
separately. Set `ORFS_HOME` to that checkout, which must contain
`flow/util/docker_shell`. Defaults are the sibling `../OpenROAD-flow-scripts`
and image `openroad/orfs:latest`; use a fixed image tag for reproducible work.

Set `RENDER_OPTION.SYNTH=true` in `rtl/config.json`, then run:

```bash
make orfs ORFS_HOME=/path/to/OpenROAD-flow-scripts \
    ORFS_IMAGE=openroad/orfs:latest DEFAULT_GOAL=floorplan

make orfs ORFS_HOME=/path/to/OpenROAD-flow-scripts \
    ORFS_IMAGE=openroad/orfs:latest DEFAULT_GOAL=all
```

Stopping goals include `synth`, `floorplan`, `place`, `cts`, `route`, `finish`,
and `all`. The example uses Nangate45 and the constraints in
`openroad/top_module.sdc`. Logs, reports, and implementation results live under
`openroad/output/`. Reporting defaults to `QT_QPA_PLATFORM=offscreen` for use
over SSH; interactive GUI targets require a working display and
`QT_QPA_PLATFORM=xcb`.

Restore `RENDER_OPTION.SYNTH=false` before cocotb tests. OpenROAD is not part of
`make check`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `rtl/` | CPU components, UART example, configuration, and source manifest |
| `dv/cocotb_benches/` | Python verification suites and helpers |
| `dv/cocotb_wrappers/` | Unit-test tops and shared ideal SPI RAM |
| `dv/` | SystemVerilog testbench and simulation source list |
| `cpp/` | DPI ideal-memory implementation |
| `misc/` | RTL renderer and unit-test runner |
| `lint/` | Verilator lint configuration |
| `third_party/` | BaseJump STL and Taxi submodules |
| `synth/` | Generic Yosys and FPGA flows |
| `openroad/` | Optional ORFS configuration and timing constraints |
| `build/` | Generated RTL, simulations, traces, and coverage |

`make clean` removes generated builds, traces, coverage, OpenROAD output, and
Vivado build output. It preserves source files and `venv/`.
