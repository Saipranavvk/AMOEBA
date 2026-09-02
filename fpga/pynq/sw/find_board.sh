#!/usr/bin/env bash
# Find the PYNQ board, over serial and over Ethernet, in one pass.
#
#     sudo ./find_board.sh
#
# Run it as root.  Every check here needs either the dialout group (serial) or
# CAP_NET_ADMIN (assigning an address), and asking for the password once beats
# discovering the third check also needed it.
#
# The checks are ordered so that each one, if it succeeds, makes the rest
# unnecessary -- and if it fails, narrows what is left.  Nothing here writes to
# the SD card or reprograms anything; it is all observation.

set -u

CON=pynq
HOST_IP=192.168.2.1/24
BOARD_IP=192.168.2.99

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mno\033[0m    %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }
warn() { printf '  \033[33m?\033[0m     %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "run me as root:  sudo $0" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- serial ----
# Which ttyUSB is the UART is not guaranteed by numbering, but it IS knowable:
# the FT2232H exposes channel A as USB interface 0 (JTAG on this board) and
# channel B as interface 1 (the console).  Read it rather than guessing.
say "FT2232 channels"
UART_TTY=
for i in /sys/bus/usb/devices/*:*; do
    [ -e "$i/bInterfaceNumber" ] || continue
    tty=$(ls "$i" 2>/dev/null | grep -o 'ttyUSB[0-9]*' | head -1)
    [ -n "$tty" ] || continue
    n=$(cat "$i/bInterfaceNumber")
    case "$n" in
        00) info "/dev/$tty  interface 0 -> channel A, JTAG (not a console)" ;;
        01) info "/dev/$tty  interface 1 -> channel B, UART  <-- console"
            UART_TTY=/dev/$tty ;;
        *)  info "/dev/$tty  interface $n" ;;
    esac
done
if [ -z "$UART_TTY" ]; then
    bad "no FT2232 UART channel found -- is the micro-USB cable in PROG/UART?"
else
    ok "console should be $UART_TTY"
fi

say "listening on $UART_TTY"
if [ -n "$UART_TTY" ]; then
    python3 "$HERE/probe_console.py" --port "$UART_TTY" --baud 115200 --read 3
    SERIAL_RC=$?
else
    SERIAL_RC=1
fi

# ------------------------------------------------------------- ethernet ----
# Pick the wired interface with a carrier that is not the wifi and not virtual.
say "wired interface"
IFACE=
for n in /sys/class/net/*; do
    d=$(basename "$n")
    case "$d" in lo|wl*|tailscale*|docker*|virbr*|br-*) continue ;; esac
    [ "$(cat "$n/carrier" 2>/dev/null)" = "1" ] || continue
    IFACE=$d
    break
done
if [ -z "$IFACE" ]; then
    bad "no wired interface with a carrier -- Ethernet cable seated at both ends?"
else
    ok "$IFACE, link up at $(cat /sys/class/net/$IFACE/speed 2>/dev/null) Mb/s"
    info "carrier only proves the board has power and its PHY negotiated."
    info "it says nothing about whether the PS booted."
fi

# ---------------------------------------------------------- static IPv4 ----
if [ -n "$IFACE" ]; then
    say "static address on $IFACE"
    if nmcli -t -f NAME con show 2>/dev/null | grep -qx "$CON"; then
        info "reusing existing '$CON' profile"
    else
        nmcli con add type ethernet ifname "$IFACE" con-name "$CON" \
              ipv4.method manual ipv4.addresses "$HOST_IP" \
              ipv4.never-default yes ipv6.method link-local >/dev/null \
            && ok "created '$CON' -> $HOST_IP on $IFACE" \
            || bad "nmcli add failed"
    fi
    nmcli con up "$CON" >/dev/null 2>&1 && ok "'$CON' up" || bad "'$CON' would not come up"
    ip -br addr show "$IFACE" | sed 's/^/        /'

    # The strongest boot test available, and the one that needs no agreement
    # about addressing: every booted Linux answers a ping to the all-nodes
    # link-local multicast group.  Run it only now, because it needs this
    # interface to have an fe80:: address of its own to send from.
    say "is anything alive on the link? (IPv6 all-nodes)"
    MINE=$(ip -6 -br addr show dev "$IFACE" | grep -oE 'fe80::[0-9a-f:]+' | head -1)
    if [ -z "$MINE" ]; then
        warn "no link-local address on $IFACE; skipping this test"
    else
        info "pinging ff02::1 from $MINE"
        PEERS=$(ping -6 -c 3 -W 1 -I "$IFACE" ff02::1 2>/dev/null \
                | grep -oE 'from fe80::[0-9a-f:]+' | awk '{print $2}' \
                | sort -u | grep -vx "$MINE")
        if [ -n "$PEERS" ]; then
            ok "something else on this cable is running an IP stack:"
            printf '%s\n' "$PEERS" | sed 's/^/        /'
            info "the PS is booted.  Reach it with:"
            printf '%s\n' "$PEERS" | sed "s|^|        ssh xilinx@|;s|\$|%$IFACE|"
        else
            bad "only our own address replied -- nothing else on this link is up"
        fi
    fi

    say "probing $BOARD_IP"
    if ping -c 3 -W 1 "$BOARD_IP" >/dev/null 2>&1; then
        ok "$BOARD_IP replies -- ssh xilinx@$BOARD_IP  (password xilinx)"
    else
        bad "$BOARD_IP silent; sweeping 192.168.2.0/24 for anything at all"
        for h in $(seq 1 254); do ping -c1 -W1 192.168.2.$h >/dev/null 2>&1 & done
        wait
        FOUND=$(ip -4 neigh show dev "$IFACE" | grep -v FAILED | awk '{print $1, $3}')
        if [ -n "$FOUND" ]; then
            ok "neighbours found:"; printf '%s\n' "$FOUND" | sed 's/^/        /'
        else
            bad "nothing answered ARP on the whole subnet"
        fi
    fi
fi

# ------------------------------------------------------------- verdict -----
say "verdict"
if [ "$SERIAL_RC" -eq 0 ]; then
    info "console is alive -- read the log above; that is where the answer is."
else
    cat <<'EOF'
        Silent on serial AND silent on the network, with the link negotiated.
        That combination means the board has power but the PS is not running
        code.  With the boot jumper confirmed on SD, what is left is the card:

          - BOOT.BIN missing from the FAT partition, or the card written as a
            file copy rather than an image (an unwritten MBR boots nothing)
          - a PYNQ-Z1 image on a Z2, which hangs in the FSBL before first print
          - a card the BootROM cannot read (some SDXC/UHS cards, or a bad write)

        Before reflashing, verify what is on it -- put the card in your laptop
        and run:   fpga/pynq/sw/check_sdcard.sh
EOF
fi
echo
