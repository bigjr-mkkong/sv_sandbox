import os
import sys

def process_flist(input_paths, output_path="IPs.flist"):
    cwd = os.getcwd()

    with open(output_path, "w") as out_file:
        for flist_path in input_paths:
            base_dir = os.path.dirname(os.path.abspath(flist_path))
            with open(flist_path, "r") as f:
                for line in f:
                    stripped = line.strip()
                    if not stripped or stripped.startswith("#"):
                        continue  # Skip empty lines and comments

                    # Path relative to cwd
                    rel_path = os.path.relpath(os.path.join(base_dir, stripped), cwd)
                    full_path = os.path.join(cwd, rel_path)

                    print(full_path)
                    out_file.write(full_path + "\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python merge_flist_relative_to_cwd.py <flist1> <flist2> ...")
        sys.exit(1)

    flist_files = sys.argv[1:]
    process_flist(flist_files)

