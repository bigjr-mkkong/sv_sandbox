
# SystemVerilog Template

This project demonstrates a scalable SystemVerilog project template. It implements an overengineered uart-axi example working on multiple synthesis and simulation targets(still on-going)

## Dependencies

* <https://github.com/YosysHQ/oss-cad-suite-build/releases>
* <https://github.com/zachjs/sv2v/releases>
* <https://www.xilinx.com/support/download.html>

## Running

```bash
git submodule update --init --recursive

# simulate with Verilator
make sim

# simulate with cocotb + Verilator
make sim-cocotb

# generic synthesis with Yosys, then simulate with Verilator
make gls

# generic synthesis with Yosys, then simulate with Verilator + cocotb
make gls-cocotb

# Icebreaker synthesis with Yosys/Icestorm, then simulate with Verilator
make icestorm_icebreaker_gls

# Icebreaker synthesis with Yosys/Icestorm, then simulate with Verilator + cocotb
# cocotb post-synthesis on fpga target will use dv bench under dv/ICE_cocotb_benches
make icestorm_icebreaker_gls-cocotb

# program Icebreaker volatile memory
make icestorm_icebreaker_program

# program Icebreaker non-volatile memory
make icestorm_icebreaker_flash
```

## File Explanations

### [`".github/workflows"`](./.github/workflows)

GitHub actions are set up to download the latest open-source tools and run all Makefile commands.

For `cocotb-base` branch, you can ignore this

### [`"dv"`](./dv) Design Verification
The `"dv"` directory holds all testbenches and generic non-synthesizable code.

* The `top_module_runner` module in [`"dv/top_module_runner.sv"`](./dv/top_module_runner.sv) abstracts away the specifics for interfacing with the top module.
* [`"dv/dv.flist"`](./dv/dv.flist) contains several useful Verilator simulation arguments: <https://veripool.org/guide/latest/exe_verilator.html>.

### [`"misc"`](./misc) Miscellaneous Script(s)

[`"misc/convert_filelist.py"`](./misc/convert_filelist.py) helps convert Verilator `.f` files into a format that can be interpreted by other tools. It may be overkill for most projects, but is quite useful when managing a lot of files.

[`"misc/rtl_renderer.py"`](./misc/rtl_renderer.py) is the pre-processor based on [jinja2][https://jinja.palletsprojects.com/en/stable/]. It may be overkill for most projects, but is quite useful when there are multiple IPs for configuration.

[`"misc/third_party_flist.py"`](./misc/third_party_flist.py) helps convert third party IPs' flist into absolute path. For some third party IP which might include multiple verilog files, it's cumbersome to add them one by one into flist. This script will read the corresponded flist from thirf part IP and copy all file paths into one single flist called `IPs.flist`.

### [`"rtl"`](./rtl) (Register Transfer Level) Synthesizable SystemVerilog

The `"rtl"` directory holds all synthesizable SystemVerilog, custom created for this project. Any IP should be included via `"third_party"`.

[`"rtl/rtl.flist"`](./rtl/rtl.flist) lists all required RTL files in the project, including those from `"third_party"`.

### [`"synth/yosys_generic"`](./synth/yosys_generic) Yosys Generic Target

The purpose of the "yosys_generic" target is to run "gate-level" or "post-synthesis" simulation (GLS).

* [`"synth/yosys_generic/yosys.tcl"`](./synth/yosys_generic/yosys.tcl): This is the TCL file to be passed to Yosys to perform generic synthesis. Note that [`prep`](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/prep.html) is run instead of [`synth`](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/synth.html) to limit the number of optimizations being run.
* [`"synth/yosys_generic/gls.f"`](./synth/yosys_generic/gls.f): This file lists all the required RTL files to be simulated in `make gls`. Note that the Yosys generic techlib is included for simulation purposes: <https://github.com/YosysHQ/yosys/blame/main/techlibs/common/simlib.v>.

* [`"synth/yosys_generic/top_module_sim_gls.sv"`](./synth/yosys_generic/top_module_sim_gls.sv): This file is a wrapper that instantiates the parameterized `top_module` module, ensuring compatibility with Yosys by eliminating parameters at the top level. It also provides a central location to define any necessary parameters.

### [`"synth/icestorm_icebreaker"`](./synth/icestorm_icebreaker) Icebreaker Target with Icestorm Flow

The purpose of the "icestorm_icebreaker" target is for simulation and FPGA implementation.

* [`"synth/icestorm_icebreaker/icebreaker.v"`](./synth/icestorm_icebreaker/icebreaker.v): This is the top-level module that exposes the Icebreaker's ports. Note the PLL that was created using `icepll`.
* [`"synth/icestorm_icebreaker/netpnr.pcf"`](./synth/icestorm_icebreaker/netpnr.pcf): This Pin Constraints File is given to `nextpnr` to assign Verilog ports to the FPGA's pins.
* [`"synth/icestorm_icebreaker/nextpnr.py"`](./synth/icestorm_icebreaker/nextpnr.py): This file is given to the `nextpnr` Python API to create timing constraints.
* [`"synth/icestorm_icebreaker/yosys.tcl"`](./synth/icestorm_icebreaker/yosys.tcl): This TCL file is passed to Yosys to perform synthesis mapped to iCE40 standard cells ([`"ice40/cells_sim.v"`](https://github.com/YosysHQ/yosys/blob/main/techlibs/ice40/cells_sim.v)).
* [`"synth/icestorm_icebreaker/gls.f"`](./synth/icestorm_icebreaker/gls.f): This file lists all the required RTL files to be simulated in `make icestorm_icebreaker_gls`.

### [`"third_party"`](./third_party) Code From Outside This Project

`"third_party"` should contain Git submodules and other code originating from other projects or sources.

### [`"lint"`](./lint) Files

Verilator Configuration File documentation: <https://veripool.org/guide/latest/exe_verilator.html#configuration-files>.

### [`"Makefile"`](./Makefile)

The Makefile creates and manages all the intermediate files created by each tool.
