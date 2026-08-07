#!/bin/bash

set -e

SIM=vcs
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim) SIM="$2"; shift 2 ;;
        *) echo "Usage: $0 [--sim vcs|verilator]" >&2; exit 1 ;;
    esac
done

case "$SIM" in
    vcs)
        LOG="vcs/simulation.log"
        ;;
    verilator)
        LOG="verilator/simulation.log"
        ;;
    *)
        echo "Unknown simulator: $SIM (use vcs or verilator)" >&2
        exit 1
        ;;
esac

grep -qE 'Monitor: (Total|Segment) IPC: +?([0-9]+?\.[0-9]+?)$' "$LOG"
sed -nr 's/Monitor: (Total|Segment) IPC: +?([0-9]+?\.[0-9]+?)$/\2/p' "$LOG"
