#!/usr/bin/env bash
# Verify a PYNQ SD card before blaming it -- or after reflashing it.
#
#     sudo ./check_sdcard.sh              # auto-detect the removable device
#     sudo ./check_sdcard.sh /dev/sdb     # or name it
#
# Reflashing takes twenty minutes and tells you nothing if the card was already
# fine.  Every failure below is one the board reports identically: a dark
# console and no network.  This distinguishes them in about ten seconds.
#
# Read-only.  It mounts partitions at a temporary point and unmounts them.

set -u

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mBAD\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33m?\033[0m     %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run me as root:  sudo $0 [device]" >&2; exit 1; }

DEV="${1:-}"
if [ -z "$DEV" ]; then
    say "looking for a removable card"
    CANDIDATES=$(lsblk -dno NAME,RM,TYPE,SIZE | awk '$2==1 && $3=="disk" {print "/dev/"$1" "$4}')
    if [ -z "$CANDIDATES" ]; then
        bad "no removable disk found -- is the card in the reader?"
        info "if your reader shows up as non-removable, pass the device:"
        info "  lsblk        then      sudo $0 /dev/sdX"
        exit 1
    fi
    N=$(printf '%s\n' "$CANDIDATES" | wc -l)
    if [ "$N" -gt 1 ]; then
        bad "more than one removable disk; name the one you mean:"
        printf '%s\n' "$CANDIDATES" | sed 's/^/        /'
        exit 1
    fi
    DEV=$(printf '%s\n' "$CANDIDATES" | awk '{print $1}')
    ok "using $DEV ($(printf '%s\n' "$CANDIDATES" | awk '{print $2}'))"
fi

[ -b "$DEV" ] || { bad "$DEV is not a block device"; exit 1; }

RC=0

say "partition table"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL "$DEV" | sed 's/^/        /'
PTTYPE=$(blkid -p -s PTTYPE -o value "$DEV" 2>/dev/null)
case "$PTTYPE" in
    dos) ok "MBR partition table (what the Zynq BootROM expects)" ;;
    gpt) warn "GPT.  The BootROM wants MBR; some images still work via a"
         info "protective MBR, but a plain GPT card will not boot." ; RC=1 ;;
    "")  bad "no partition table at all -- the card was never imaged."
         info "This is what you get from copying files onto a formatted card"
         info "instead of writing the .img with dd or Etcher."; RC=1 ;;
    *)   warn "partition table type '$PTTYPE'" ;;
esac

# Find the FAT and ext4 partitions by filesystem, not by number.
BOOTP=; ROOTP=
for p in $(lsblk -lno NAME "$DEV" | tail -n +2); do
    d=/dev/$p
    case "$(blkid -s TYPE -o value "$d" 2>/dev/null)" in
        vfat)  [ -z "$BOOTP" ] && BOOTP=$d ;;
        ext4)  [ -z "$ROOTP" ] && ROOTP=$d ;;
    esac
done

MNT=$(mktemp -d)
cleanup() { umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null; }
trap cleanup EXIT

say "boot partition (FAT)"
if [ -z "$BOOTP" ]; then
    bad "no FAT partition -- the BootROM has nothing to read"; RC=1
else
    ok "$BOOTP"
    if mount -o ro "$BOOTP" "$MNT" 2>/dev/null; then
        ls -la "$MNT" | sed 's/^/        /'

        if [ -f "$MNT/BOOT.BIN" ]; then
            SZ=$(stat -c%s "$MNT/BOOT.BIN")
            ok "BOOT.BIN present, $SZ bytes"
            # Zynq-7000 boot header: width-detection word 0xAA995566 at 0x20,
            # image identification "XNLX" at 0x24.  A file that fails this is
            # not a boot image, whatever it is called.
            W=$(xxd -s 0x20 -l 4 -e -g4 "$MNT/BOOT.BIN" 2>/dev/null | awk '{print $2}')
            ID=$(xxd -s 0x24 -l 4 -p "$MNT/BOOT.BIN" 2>/dev/null | xxd -r -p)
            if [ "$W" = "aa995566" ] && [ "$ID" = "XNLX" ]; then
                ok "valid Zynq boot header (0xAA995566 / 'XNLX')"
            else
                bad "not a Zynq boot image: width=0x$W id='$ID'"
                info "expected width=0xaa995566 id='XNLX'"; RC=1
            fi
        else
            bad "no BOOT.BIN -- the BootROM will find nothing to run."
            info "This alone explains a completely dark board."; RC=1
        fi

        for f in image.ub boot.scr uImage devicetree.dtb; do
            [ -e "$MNT/$f" ] && ok "$f present"
        done
        [ -e "$MNT/image.ub" ] || [ -e "$MNT/uImage" ] || {
            warn "no kernel image (image.ub / uImage) on the FAT partition"
            info "u-boot may load it from elsewhere, but on a stock PYNQ card"
            info "image.ub lives here."; }
        umount "$MNT"
    else
        bad "could not mount $BOOTP"; RC=1
    fi
fi

say "root filesystem (ext4)"
if [ -z "$ROOTP" ]; then
    bad "no ext4 partition -- there is no rootfs to boot into"; RC=1
else
    ok "$ROOTP"
    if mount -o ro "$ROOTP" "$MNT" 2>/dev/null; then
        # The single most useful thing in here: which board the image is for.
        # A Z1 image on a Z2 is the classic silent failure.
        if [ -f "$MNT/etc/environment" ]; then
            B=$(grep -i '^BOARD=' "$MNT/etc/environment" | cut -d= -f2- | tr -d '"')
            if [ -n "$B" ]; then
                case "$B" in
                    *Z2*|*z2*) ok "image is built for BOARD=$B" ;;
                    *) bad "image is built for BOARD=$B -- this is a PYNQ-Z2."
                       info "A Z1 image hangs before it prints anything."; RC=1 ;;
                esac
            else
                warn "no BOARD= line in /etc/environment"
            fi
        fi
        [ -f "$MNT/etc/os-release" ] && \
            grep -E '^(PRETTY_NAME|VERSION)=' "$MNT/etc/os-release" | sed 's/^/        /'
        for v in "$MNT"/usr/local/share/pynq-venv "$MNT"/usr/local/lib/python3*/dist-packages/pynq; do
            [ -e "$v" ] && { ok "pynq installed ($(basename "$v"))"; break; }
        done
        [ -d "$MNT/home/xilinx" ] && ok "/home/xilinx exists" || {
            warn "no /home/xilinx -- not a stock PYNQ rootfs"; }
        umount "$MNT"
    else
        bad "could not mount $ROOTP (needs ext4 support; you are on Linux, so"
        info "this more likely means the filesystem is damaged)"; RC=1
    fi
fi

say "verdict"
if [ "$RC" -eq 0 ]; then
    info "The card looks correct and bootable.  If the board is still dark,"
    info "the card is not the problem -- suspect power, the boot-mode jumper,"
    info "or the card reader in the board itself."
else
    info "Something above is wrong with this card.  Reflash it:"
    info "  the PYNQ v3.1 Z2 image, written with dd or Etcher to the whole"
    info "  device (/dev/sdX, not /dev/sdX1), then re-run this script."
fi
echo
exit "$RC"
