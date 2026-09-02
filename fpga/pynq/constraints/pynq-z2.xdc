###############################################################################
# pynq-z2.xdc
#
# This design has NO PL I/O, and that is not an omission.
#
# The PS7's DDR and FIXED_IO pins are placed by the board preset, not from here.
# The PL clock is FCLK_CLK0 from inside the PS7, so it is constrained by the
# PS7's own IP-level XDC and must NOT be given a create_clock here -- doing so
# creates a second, conflicting clock on the same net.  Everything the host
# talks to goes over AXI.  That leaves nothing to place.
#
# There used to be two PMODA pins here for a serial console.  They were removed
# because the console the PS reads is the AHB snoop in amoeba_bus_mon, and a
# physical UART is redundant with it, would emit garbage without per-clock
# retuning of the guest's baud divisor (FCLK_CLK0 is 25 MHz; the drivers assume
# the simulation's 100 MHz), and tests PL scaffolding rather than anything that
# goes to the ASIC.  See the header of rtl/amoeba_pynq_top.sv.
#
# If you do bring a signal out, the PMODA mapping from the installed board file
# (.../board_files/.../pynq-z2/A.0/part0_pins.xml) is:
#
#   JA1  Y18      JA7   U18        pin 5  GND     pin 11  GND
#   JA2  Y19      JA8   U19        pin 6  VCC     pin 12  VCC
#   JA3  Y16      JA9   W18
#   JA4  Y17      JA10  W19
#
# All 3.3 V, with 200 ohm series protection resistors.  CAUTION: on the PYNQ-Z2
# these pins are physically shared with the Raspberry Pi 40-pin header -- the
# same board file lists Y18/Y19 as raspberry_pi_tri_i_2/3.  PMODB is not shared:
# JB1 = W14, JB2 = Y14.
#
# This file is still added by tcl/build.tcl, so it is the place to put timing
# exceptions or debug-core constraints when they are needed.
###############################################################################
