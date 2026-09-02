#!/usr/bin/env bash
# Copy the driver, the bitstream and a program image to a PYNQ board.
#
#   ./deploy.sh [user@host] [image.elf ...]
#
# Defaults to xilinx@192.168.2.99, which is what a PYNQ-Z2 self-assigns on a
# direct Ethernet link to a laptop.  Everything lands in ~/amoeba on the board:
#
#   ~/amoeba/amoeba.bit  amoeba.hwh      the overlay
#   ~/amoeba/sw/                          this package
#   ~/amoeba/images/                      program images
#
# and the notebook is linked into the Jupyter tree so it shows up in the browser.
set -euo pipefail

BOARD=${1:-xilinx@192.168.2.99}
shift || true

HERE=$(cd "$(dirname "$0")" && pwd)
FPGA=$(dirname "$HERE")
BITDIR=${BITDIR:-$FPGA/bit/baremetal_linux-BRAM}
DEST=${DEST:-amoeba}
JUPYTER=${JUPYTER:-jupyter_notebooks}

[[ -f $BITDIR/amoeba.bit ]] || { echo "no bitstream at $BITDIR/amoeba.bit -- run 'make bitstream'"; exit 1; }

echo "deploying to $BOARD:~/$DEST"
ssh "$BOARD" "mkdir -p ~/$DEST/images ~/$JUPYTER/amoeba"

# --exclude __pycache__: stale .pyc for a different Python version on the board
# is a genuinely confusing failure.
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' \
      "$HERE/" "$BOARD:$DEST/sw/"
rsync -a "$BITDIR/amoeba.bit" "$BITDIR/amoeba.hwh" "$BOARD:$DEST/"

# Mirror, do not accumulate.  Copying images in one at a time leaves whatever
# a previous deploy put there, and a stale non-terminating image sitting in
# that directory gets picked up by the regression runner and burns a timeout.
# --delete makes the board's images/ exactly what you just deployed.
if (( $# )); then
    for img in "$@"; do
        [[ -f $img ]] || { echo "no such image: $img"; exit 1; }
        echo "  image: $(basename "$img")"
    done
    rsync -a --delete "$@" "$BOARD:$DEST/images/"
else
    echo "  (no images given; leaving ~/$DEST/images alone)"
fi

# The notebook is a symlink into the Jupyter tree rather than a copy, so editing
# it on the board does not silently diverge from the one in the repo.
ssh "$BOARD" "ln -sf ~/$DEST/sw/amoeba_demo.ipynb ~/$JUPYTER/amoeba/amoeba_demo.ipynb"

cat <<MSG

deployed.  Two ways to run it:

  SSH:
    ssh $BOARD
    cd ~/$DEST/sw
    sudo python3 run_freertos.py --bitstream ../amoeba.bit \\
         --image ../images/freertos_wally.elf --soak 30

  Jupyter:
    open http://${BOARD#*@}:9090  (password: xilinx)
    then amoeba/amoeba_demo.ipynb

MSG
