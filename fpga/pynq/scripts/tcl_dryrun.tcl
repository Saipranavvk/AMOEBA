# Dry-run harness for tcl/synth_ooc.tcl -- exercises the script's control flow,
# argument handling and report calls with every Vivado command stubbed out.
#
#   tclsh scripts/tcl_dryrun.tcl <srcs.f>
#
# Catches typos, bad lassign arity and malformed command construction in
# seconds, instead of an hour into a synthesis run on a machine that has
# Vivado.  It proves the script runs; it cannot prove Vivado likes the options.

set called {}
proc note {name args} {
    global called
    lappend called $name
    puts "  \[stub\] $name [string range $args 0 90]"
}
foreach cmd {read_verilog read_xdc synth_design
             report_timing_summary report_timing write_checkpoint} {
    proc $cmd args "note $cmd {*}\$args"
}

# report_utilization is not a pure stub: synth_ooc.tcl parses its -return_string
# output for every number in summary.txt, so the stub has to hand back a table
# with the real row names and column layout.  Otherwise the dry run silently
# proves nothing about the part of the script most likely to be wrong.
proc report_utilization args {
    note report_utilization {*}$args
    if {[lsearch -exact $args "-return_string"] < 0} { return }
    return {+----------------------------+-------+-------+------------+-----------+-------+
|          Site Type         |  Used | Fixed | Prohibited | Available | Util% |
+----------------------------+-------+-------+------------+-----------+-------+
| Slice LUTs*                | 11119 |     0 |          0 |     53200 | 20.90 |
|   LUT as Logic             | 10703 |     0 |          0 |     53200 | 20.12 |
| Slice Registers            |  7996 |     0 |          0 |    106400 |  7.52 |
+----------------------------+-------+-------+------------+-----------+-------+
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |    8 |     0 |          0 |       140 |  5.71 |
+-------------------+------+-------+------------+-----------+-------+
+----------------+------+-------+------------+-----------+-------+
| DSPs           |   16 |     0 |          0 |       220 |  7.27 |
+----------------+------+-------+------------+-----------+-------+}
}

# Queries that return values the script uses.
proc get_cells args        { return [lrepeat 1234 cell] }
proc get_ports args        { return [list port0] }
proc get_clocks args       { return [list clk] }
proc get_timing_paths args { return path0 }
proc get_property {prop obj} {
    if {$prop eq "SLACK"} { return 3.217 }
    return ""
}

set srcs_f [lindex $argv 0]
set argv [list $srcs_f amoeba_soc_wrapper xc7z020clg400-1 40.000 \
               [file join [file dirname $srcs_f] dryrun_reports] \
               AMOEBA_CONFIG_BAREMETAL_LINUX "/inc/a /inc/b" clk reset_ext]
set argc [llength $argv]

source [file join [file dirname [info script]] .. tcl synth_ooc.tcl]
