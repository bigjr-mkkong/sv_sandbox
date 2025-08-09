import os
import re
from jinja2 import Environment, FileSystemLoader

# I will use jinja2 as the pre-processor engine for this sv template

UART0 = {
        "exist": True,
        "AXI_DATAW": 8,
        "PRE_W": 16,
        "BAUD": 115200,
        "Fclk": 48000000,
        }
UART0["PRE_VAL"] = int(UART0["Fclk"] / (UART0["BAUD"] * 8))

Configs = {
        "UART0": UART0
        }

template_dir = "rtl/"
output_dir = "_rtl/"

env = Environment(loader=FileSystemLoader(template_dir))

for root, _, files in os.walk(template_dir):
    for filename in files:
        rel_input_path = os.path.relpath(os.path.join(root, filename), template_dir)
        full_input_path = os.path.join(root, filename)
        output_path = os.path.join(output_dir, rel_input_path)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        if filename.endswith(".sv") or \
                filename.endswith(".svh") or\
                filename.endswith("v"):

            template = env.get_template(rel_input_path)
            rendered = template.render(Configs)
            with open(output_path, "w") as f:
                f.write(rendered)
            print(f"Rendered (system)verilog: {rel_input_path} -> {output_path}")

        elif filename.endswith(".flist"):
            with open(full_input_path, "r") as f_in, open(output_path, "w") as f_out:
                for line in f_in:
                    f_out.write(re.sub(r'^rtl/', '_rtl/', line))
            print(f"Rendered flist: {rel_input_path} -> {output_path}")

