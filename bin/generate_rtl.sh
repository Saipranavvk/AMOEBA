#!/usr/bin/env bash
# Two-stage RTL generation for AMOEBA:
#
#   Stage 1 — hdl/cvw/   : pristine verbatim copy of third_party/cvw/src/
#                           Always refreshed from the submodule. NEVER edit this directory.
#
#   Stage 2 — hdl/core/  : working copy derived from hdl/cvw/
#                           Created on first run; NOT overwritten on subsequent runs so
#                           that AMOEBA-specific edits are preserved.
#                           Pass --reset to wipe and regenerate from hdl/cvw/.
#
# Usage (from repo root):
#   bash bin/generate_rtl.sh          # refresh hdl/cvw/, create hdl/core/ if absent
#   bash bin/generate_rtl.sh --reset  # refresh hdl/cvw/, wipe and recreate hdl/core/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CVW_SRC="${REPO_ROOT}/third_party/cvw/src"
HDL_CVW="${REPO_ROOT}/hdl/cvw"
HDL_CORE="${REPO_ROOT}/hdl/core"
RESET=0

for arg in "$@"; do
    case "$arg" in
        --reset) RESET=1 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ---- Stage 1: refresh hdl/cvw/ ----
if [[ ! -f "${CVW_SRC}/cvw.sv" ]]; then
    echo "ERROR: CVW source not found at ${CVW_SRC}"
    echo "       Run:  git submodule update --init third_party/cvw"
    exit 1
fi

echo "Stage 1: refreshing hdl/cvw/ from third_party/cvw/src/ ..."
rm -rf "${HDL_CVW}"
cp -r "${CVW_SRC}" "${HDL_CVW}"
count=$(find "${HDL_CVW}" -name "*.sv" -o -name "*.v" | wc -l)
echo "         ${count} files written to hdl/cvw/"

# ---- Stage 2: generate hdl/core/ ----
if [[ -d "${HDL_CORE}" && "${RESET}" -eq 0 ]]; then
    echo "Stage 2: hdl/core/ already exists — skipping (pass --reset to regenerate)."
else
    echo "Stage 2: generating hdl/core/ from hdl/cvw/ ..."
    rm -rf "${HDL_CORE}"
    cp -r "${HDL_CVW}" "${HDL_CORE}"
    count=$(find "${HDL_CORE}" -name "*.sv" -o -name "*.v" | wc -l)
    echo "         ${count} files written to hdl/core/"
fi

echo "Done."
