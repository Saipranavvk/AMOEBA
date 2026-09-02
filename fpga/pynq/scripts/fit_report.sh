#!/usr/bin/env bash
# Turn a Vivado OOC synthesis run into the one table the gate exists to produce:
# does it fit an XC7Z020, with how much room, and at what clock.
#
#   fit_report.sh <report_dir> <config_tag>
#
# Post-synthesis numbers are estimates -- placement can push LUT usage up as the
# tool duplicates logic to meet timing.  Treat anything above ~80% here as "run
# place-and-route before believing it fits."
set -euo pipefail

DIR=${1:?usage: fit_report.sh <report_dir> <config_tag>}
TAG=${2:-?}

SUM="$DIR/summary.txt"
if [[ ! -f $SUM ]]; then
    echo "fit_report: no summary at $SUM (synthesis did not complete)" >&2
    exit 1
fi

get() { awk -v k="$1" '$1==k {print $2}' "$SUM"; }

# XC7Z020-1CLG400 capacities.
CAP_LUT=53200
CAP_REG=106400
CAP_DSP=220
CAP_BRAM=140      # RAMB36E1; a design using RAMB18 counts halves

LUT=$(get luts);  REG=$(get regs)
DSP=$(get dsps);  BRAM=$(get brams)
WNS=$(get wns_ns); PERIOD=$(get period_ns)

pct() { awk -v a="$1" -v b="$2" 'BEGIN{ if (b==0) print "-"; else printf "%.1f", 100*a/b }'; }

FMHZ=$(awk -v p="$PERIOD" 'BEGIN{printf "%.1f", 1000/p}')
# Achievable clock from the worst negative slack: the period that would give
# exactly zero slack.
if [[ -n ${WNS:-} ]]; then
    FMAX=$(awk -v p="$PERIOD" -v w="$WNS" 'BEGIN{ d=p-w; if (d<=0) print "-"; else printf "%.1f", 1000/d }')
else
    FMAX="-"
fi

printf '\n'
printf '  XC7Z020 fit -- CONFIG=%s   @ %s MHz target\n' "$TAG" "$FMHZ"
printf '  %s\n' '--------------------------------------------------------'
printf '  %-10s %9s / %-9s %6s%%\n' "LUT6"  "$LUT"  "$CAP_LUT"  "$(pct "$LUT"  $CAP_LUT)"
printf '  %-10s %9s / %-9s %6s%%\n' "FF"    "$REG"  "$CAP_REG"  "$(pct "$REG"  $CAP_REG)"
printf '  %-10s %9s / %-9s %6s%%\n' "DSP48"  "$DSP" "$CAP_DSP"  "$(pct "$DSP"  $CAP_DSP)"
printf '  %-10s %9s / %-9s %6s%%\n' "BRAM36" "$BRAM" "$CAP_BRAM" "$(pct "$BRAM" $CAP_BRAM)"
printf '  %s\n' '--------------------------------------------------------'
printf '  %-10s %9s ns   -> Fmax %s MHz\n' "WNS" "${WNS:-?}" "$FMAX"

# Report every resource that is over, not just the last one checked.
over() { awk -v a="$1" -v c="$2" 'BEGIN{exit !(a>c)}'; }

OVER=()
over "$LUT"  $CAP_LUT  && OVER+=(LUT)   || true
over "$REG"  $CAP_REG  && OVER+=(FF)    || true
over "$DSP"  $CAP_DSP  && OVER+=(DSP)   || true
over "$BRAM" $CAP_BRAM && OVER+=(BRAM)  || true

if (( ${#OVER[@]} )); then
    VERDICT="DOES NOT FIT (${OVER[*]})"
elif over "$LUT" $(awk -v c=$CAP_LUT 'BEGIN{print 0.8*c}'); then
    # Post-synthesis is an estimate; placement can push LUT usage up as the
    # tool duplicates logic to meet timing.
    VERDICT="TIGHT -- run place-and-route before believing it"
else
    VERDICT="FITS"
fi
printf '  %-10s %s\n\n' "verdict" "$VERDICT"

# Where the area went, so the cache decision has evidence.
if [[ -f $DIR/utilization_hier.rpt ]]; then
    echo "  largest hierarchy cells (from utilization_hier.rpt):"
    awk '/^\|[[:space:]]*[a-zA-Z_]/ {print}' "$DIR/utilization_hier.rpt" \
        | head -14 | sed 's/^/    /'
    echo
fi
