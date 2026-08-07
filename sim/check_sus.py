#!/usr/bin/python3

import subprocess
import os
import sys
import string

allowed_sv_tasks = [
    "signed",
    "unsigned",
    "cast",
    "bits",
    "unpacked_dimensions",
    "dimensions",
    "left",
    "right",
    "low",
    "high",
    "increment",
    "size",
    "clog2",
    "countbits",
    "countones",
    "onehot",
    "onehot0",
    "fatal",
]
# backtick removed — preprocessor directives (`include/`ifdef/`ifndef/`endif) are
# allowed in hdl/ because CVW's config chain requires them in rv64_core_wrapper.sv.
# DPI is still banned separately.
sus_keywords = ["DPI", "verilator", "xprop_off", "translate_off", "dc_tcl_script_begin", "dc_script_begin"]
# banned_wholewords only applied to hdl/ (not pkg/types.sv which uses parameter int legitimately)
banned_wholewords = ["bit", "int", "byte", "shortint", "longint", "real", "shortreal", "time"]
search_dir_all  = ["hdl", "pkg"]  # checked for sus_keywords and $ system tasks
search_dir_hdl  = ["hdl"]         # checked for banned_wholewords
exclude_dirs = ["cvw", "core"]
allowed_char = set(string.ascii_lowercase + string.ascii_uppercase + string.digits + "._-/")

os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.chdir("..")

found = False
log = ""

# Filename check (all dirs, exclude cvw)
for d in search_dir_all:
    result = subprocess.run(f"find {d} -not -path '{d}/cvw/*' -not -path '{d}/core/*'", shell=True, stdout=subprocess.PIPE)
    files = result.stdout.decode().split('\n')
    for f in files:
        if not set(f.strip()) <= allowed_char:
            found = True
            log += f + '\n'

allowed_sv_tasks_pat = '|'.join(allowed_sv_tasks)
exclude_grep = ' '.join(f'--exclude-dir={e}' for e in exclude_dirs)
# types.sv uses /* verilator lint_off */ block comments for Verilator suppressors — exclude from keyword scan
sv_only = '--include=*.sv --exclude=types.sv'
search_all = ' '.join(search_dir_all)
search_hdl  = ' '.join(search_dir_hdl)

# Forbidden $ system tasks (exclude comments)
result = subprocess.run(
    f"grep -Rn -P '\\$(?!({allowed_sv_tasks_pat}))' {exclude_grep} {sv_only} {search_all}"
    r" | grep -Pv '^\S+:\d+:\s*//'",
    shell=True, stdout=subprocess.PIPE
)
if result.returncode != 1:
    found = True
    log += result.stdout.decode()

# Forbidden keywords (DPI, verilator in code, xprop directives, etc.) — exclude comment lines
for s in sus_keywords:
    result = subprocess.run(
        f"grep -Rn -P '{s}' {exclude_grep} {sv_only} {search_all}"
        r" | grep -Pv '^\S+:\d+:\s*//'",
        shell=True, stdout=subprocess.PIPE
    )
    if result.returncode != 1:
        found = True
        log += result.stdout.decode()

# Banned C-style types — only scan hdl/ (pkg/types.sv uses parameter int legitimately)
# Also exclude comment-only lines
for s in banned_wholewords:
    result = subprocess.run(
        f"grep -Rnw '{s}' {exclude_grep} {sv_only} {search_hdl}"
        r" | grep -Pv '^\S+:\d+:\s*//'",
        shell=True, stdout=subprocess.PIPE
    )
    if result.returncode != 1:
        found = True
        log += result.stdout.decode()

if found:
    print("\033[31m" + "Forbidden Keyword Found: " + "\033[0m", file=sys.stderr)
    print(log, file=sys.stderr)
    exit(1)
else:
    exit(0)
