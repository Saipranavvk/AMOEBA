###############################################################################
# bd_pynq.tcl -- the PYNQ-Z2 block design.
#
# Builds the PS side of what fpga/pynq/DESIGN.md describes: a Zynq PS7, one
# clock, one reset, and the three paths the PL top needs.
#
#   GP0 -> interconnect -> s_axi_ctl   (4 KiB)   control and status
#                       -> s_axi_mem   (MEM_KB)  program image, BRAM builds
#   HP0 <- axi_dma S2MM <- m_axis_trace           commit records
#   HP0 <- ahblite_axi_bridge <- m_ahb_*          DDR memory, AXI builds
#
# Sourced by build.tcl with the project already open.  Everything is
# parameterised off the same variables the Makefile passes to the synthesis
# gate, so the two cannot drift.
#
# ONE CLOCK.  FCLK_CLK0 drives the PL, both PS-facing AXI interfaces, and the
# core.  There is no CDC in this design and there should not be one: adding a
# second clock here is how you get a bug that only appears at temperature.
#
# THE BOARD PRESET IS REQUIRED FOR HARDWARE, not a convenience.  Applying it is
# what sets the DDR part, its timing and the MIO map for the PYNQ-Z2's specific
# memory.  A design built on the wrong preset synthesizes fine and then fails to
# bring DDR up, which is an expensive way to find out.  The board files do not
# ship with Vivado; see amoeba_bd_require_board below for where to get them.
#
# board = "none" skips the preset.  That is a STRUCTURAL CHECK ONLY -- it proves
# the module references elaborate, the interfaces infer, and the addresses
# assign, which is where essentially every bug in this script lives.  It cannot
# produce a working bitstream, and build.tcl refuses to try.
###############################################################################

proc amoeba_bd_require_board {board} {
    if {$board eq "none"} {
        puts "WARNING: building with NO board preset (board=none)."
        puts "         This validates the design's structure only.  DDR, MIO and"
        puts "         the PS clocking are left at Vivado's defaults, so the"
        puts "         result must not be programmed onto a board."
        return 1
    }
    if {[llength [get_board_parts -quiet $board]] == 0} {
        puts "ERROR: board part '$board' is not installed."
        puts ""
        puts "  The PYNQ-Z2 board files are not shipped with Vivado.  Either:"
        puts "    - install them through Tools > Vivado Store > Boards, or"
        puts "    - unpack them somewhere and point the build at it:"
        puts "        make bitstream BOARD_REPO=/path/to/board_files"
        puts ""
        puts "  To check the design's structure without them:"
        puts "        make bd BOARD=none"
        puts ""
        puts "  This is not optional: the preset is what configures the DDR part,"
        puts "  its timing and the MIO map for this board.  Building on a"
        puts "  different preset gives a bitstream that synthesizes and then"
        puts "  cannot bring up memory."
        return 0
    }
    return 1
}

proc amoeba_build_bd {args} {
    # ---- arguments ---------------------------------------------------------
    array set opt {
        bd_name      amoeba
        top          amoeba_pynq_top_v
        board        tul.com.tw:pynq-z2:part0:1.0
        fclk_mhz     25
        mem_backend  BRAM
        mem_kb       128
        trace        1
        ctl_base     0x43C00000
        mem_base     0x44000000
        dma_base     0x40400000
        ddr_carveout 0x10000000
        ddr_size     0x10000000
    }
    array set opt $args

    set bd   $opt(bd_name)
    set top  $opt(top)

    if {![amoeba_bd_require_board $opt(board)]} { return 0 }
    if {$opt(board) ne "none"} {
        set_property board_part $opt(board) [current_project]
    }

    create_bd_design $bd
    current_bd_design $bd

    # ---- processing system -------------------------------------------------
    set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7]
    set preset [expr {$opt(board) eq "none" ? "0" : "1"}]
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config [list make_external "FIXED_IO, DDR" apply_board_preset $preset \
                      Master "Disable" Slave "Disable"] $ps

    # GP0 for the two AXI4-Lite slaves, HP0 for the DMA and (in AXI builds) the
    # core's own memory traffic.  HP is the wide, low-latency path to DDR --
    # putting the trace on GP would share the same narrow port the control plane
    # polls through, and the two would fight.
    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0        {1} \
        CONFIG.PCW_USE_S_AXI_HP0        {1} \
        CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $opt(fclk_mhz) \
        CONFIG.PCW_EN_CLK0_PORT         {1} \
        CONFIG.PCW_EN_RST0_PORT         {1} \
    ] $ps

    # ---- clock and reset ---------------------------------------------------
    set rstgen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7]
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0]     [get_bd_pins rst_ps7/slowest_sync_clk]
    connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7/ext_reset_in]

    set aclk    [get_bd_pins ps7/FCLK_CLK0]
    set aresetn [get_bd_pins rst_ps7/peripheral_aresetn]

    # ---- the PL top --------------------------------------------------------
    # An RTL module reference, not packaged IP.  IPI infers the AXI4-Lite
    # slaves, the AXI4-Stream master and the clock/reset from the port names,
    # which is exactly why amoeba_mem_bram exposes AXI rather than a raw block
    # RAM port -- see the header of that file.
    #
    # The reference is the Verilog shim, not the SystemVerilog top: IPI refuses
    # a SystemVerilog file as a module reference's top.  See
    # rtl/amoeba_pynq_top_v.v.
    set dut [create_bd_cell -type module -reference $top dut]
    set_property -dict [list \
        CONFIG.MEM_BRAM [expr {$opt(mem_backend) eq "BRAM" ? 1 : 0}] \
        CONFIG.MEM_KB   $opt(mem_kb) \
        CONFIG.TRACE    $opt(trace) \
    ] $dut

    connect_bd_net $aclk    [get_bd_pins dut/aclk]
    connect_bd_net $aresetn [get_bd_pins dut/aresetn]

    # No ASSOCIATED_BUSIF here: on a module reference that property is
    # read-only, and IPI derives the clock association from the port names
    # itself.  Setting it is a CRITICAL WARNING that changes nothing.

    # ---- trace DMA ---------------------------------------------------------
    # S2MM only: nothing ever streams toward the PL.  Scatter-gather off keeps
    # the driver side to "write an address and a length", which is all the
    # capture loop needs, and the descriptors would otherwise have to live in
    # the same DDR the core is using in AXI builds.
    if {$opt(trace)} {
        set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma dma_trace]
        set_property -dict [list \
            CONFIG.c_include_sg           {0} \
            CONFIG.c_include_mm2s         {0} \
            CONFIG.c_include_s2mm         {1} \
            CONFIG.c_s2mm_burst_size      {16} \
            CONFIG.c_m_axi_s2mm_data_width {64} \
            CONFIG.c_sg_length_width      {26} \
        ] $dma
        connect_bd_intf_net [get_bd_intf_pins dut/m_axis_trace] \
                            [get_bd_intf_pins dma_trace/S_AXIS_S2MM]
        connect_bd_net $aclk    [get_bd_pins dma_trace/s_axi_lite_aclk]
        connect_bd_net $aclk    [get_bd_pins dma_trace/m_axi_s2mm_aclk]
        connect_bd_net $aresetn [get_bd_pins dma_trace/axi_resetn]
    }

    # ---- DDR path for AXI builds -------------------------------------------
    if {$opt(mem_backend) eq "BRAM"} {
        # The AHB master's response inputs have no driver in a BRAM build --
        # the memory is inside the PL top and answers internally.  Tie them off
        # explicitly rather than letting IPI do it: IPI's implicit tie-off is a
        # CRITICAL WARNING that looks identical to a genuinely forgotten
        # connection, and this design has enough real warnings to read.
        set z  [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant ahb_tie0]
        set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] $z
        set z64 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant ahb_tie0_64]
        set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {64}] $z64
        connect_bd_net [get_bd_pins ahb_tie0_64/dout] [get_bd_pins dut/m_ahb_hrdata]
        connect_bd_net [get_bd_pins ahb_tie0/dout]    [get_bd_pins dut/m_ahb_hready]
        connect_bd_net [get_bd_pins ahb_tie0/dout]    [get_bd_pins dut/m_ahb_hresp]
    }

    if {$opt(mem_backend) eq "AXI"} {
        set br [create_bd_cell -type ip -vlnv xilinx.com:ip:ahblite_axi_bridge ahb2axi]
        set_property -dict [list \
            CONFIG.C_M_AXI_SUPPORTS_NARROW_BURST {1} \
            CONFIG.C_M_AXI_DATA_WIDTH            {64} \
            CONFIG.C_S_AHB_DATA_WIDTH            {64} \
        ] $br
        connect_bd_net $aclk    [get_bd_pins ahb2axi/s_ahb_hclk]
        connect_bd_net $aresetn [get_bd_pins ahb2axi/s_ahb_hresetn]
        amoeba_connect_ahb dut ahb2axi
    }

    # ---- interconnects -----------------------------------------------------
    # GP0 fans out to the control block and, in BRAM builds, the image window.
    set gp0_targets [list dut/s_axi_ctl]
    if {$opt(mem_backend) eq "BRAM"} { lappend gp0_targets dut/s_axi_mem }
    if {$opt(trace)}                 { lappend gp0_targets dma_trace/S_AXI_LITE }

    foreach t $gp0_targets {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
            -config [list Master {/ps7/M_AXI_GP0} Clk "Auto"] \
            [get_bd_intf_pins $t]
    }

    # HP0 takes the DMA's write channel and, in AXI builds, the core's memory
    # traffic.  Both are masters into the PS.
    set hp0_masters {}
    if {$opt(trace)}                 { lappend hp0_masters dma_trace/M_AXI_S2MM }
    if {$opt(mem_backend) eq "AXI"}  { lappend hp0_masters ahb2axi/M_AXI }

    foreach m $hp0_masters {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
            -config [list Master [list /$m] Clk "Auto"] \
            [get_bd_intf_pins ps7/S_AXI_HP0]
    }

    # No console pins.  The console the PS reads is the AHB snoop; a physical
    # UART would be redundant with it and, at FCLK rather than the clock the
    # guest's baud divisor assumes, would emit garbage anyway.  See the header
    # of rtl/amoeba_pynq_top.sv.  This design therefore has NO PL I/O at all,
    # which is also why constraints/pynq-z2.xdc has no pin assignments in it.
    #
    # uart_txd_obs is left unconnected on purpose: it is an ILA observation
    # point, and IPI tying an unused output nowhere costs nothing.

    # ---- addresses ---------------------------------------------------------
    # Explicit offsets and ranges, assigned before the catch-all, so the PS-side
    # software has constants instead of whatever the auto-assigner happened to
    # pick this run.  Ranges matter as much as offsets: left alone, the image
    # window's 32-bit AXI-Lite address makes the auto-assigner claim 512 MB of
    # the PS map for a 128 KiB block RAM.
    amoeba_assign dut/s_axi_ctl/reg0     $opt(ctl_base) 4K
    if {$opt(mem_backend) eq "BRAM"} {
        amoeba_assign dut/s_axi_mem/reg0 $opt(mem_base) "$opt(mem_kb)K"
    }
    if {$opt(trace)} {
        amoeba_assign dma_trace/S_AXI_LITE/Reg $opt(dma_base) 64K
    }

    # The masters into DDR are clamped to the carve-out.  Left at the full
    # 512 MB, a runaway core address in an AXI build overwrites the PS kernel
    # instead of erroring, which presents as the board hanging at random; and
    # the DMA would be free to scribble anywhere the capture length allowed.
    if {$opt(trace)} {
        amoeba_assign_master dma_trace/Data_S2MM ps7/S_AXI_HP0/HP0_DDR_LOWOCM \
            $opt(ddr_carveout) $opt(ddr_size)
    }
    if {$opt(mem_backend) eq "AXI"} {
        amoeba_assign_master ahb2axi/M_AXI ps7/S_AXI_HP0/HP0_DDR_LOWOCM \
            $opt(ddr_carveout) $opt(ddr_size)
    }

    # Anything not named above -- there should be nothing -- so that a forgotten
    # interface is an unassigned segment rather than a silent hole.
    assign_bd_address -quiet

    validate_bd_design
    save_bd_design
    return 1
}

# Place one slave segment in the PS's address space at a fixed offset and range.
# assign_bd_address with an explicit -offset/-range does in one step what
# assign-then-set_property does in two, and unlike the two-step form it does not
# depend on guessing the generated segment name.
proc amoeba_assign {slave_seg base range} {
    set seg [get_bd_addr_segs -quiet $slave_seg]
    if {[llength $seg] == 0} {
        puts "WARNING: no slave segment '$slave_seg'."
        puts "         The PS-side constants for it will not match the bitstream."
        return
    }
    assign_bd_address -offset $base -range $range \
        -target_address_space [get_bd_addr_spaces ps7/Data] $seg -force
    puts "  address    : $slave_seg -> $base ($range)"
}

# Same, for a master in the PL reaching into the PS's DDR.
proc amoeba_assign_master {space slave_seg base range} {
    set sp  [get_bd_addr_spaces -quiet $space]
    set seg [get_bd_addr_segs   -quiet $slave_seg]
    if {[llength $sp] == 0 || [llength $seg] == 0} {
        puts "WARNING: cannot clamp $space -> $slave_seg; it will get the full DDR"
        return
    }
    assign_bd_address -offset $base -range $range \
        -target_address_space $sp $seg -force
    puts "  ddr window : $space -> $base ($range)"
}

# Wire the PL top's flat AHB pins to the bridge's AHB interface pins.  These are
# individual nets rather than an interface connection because the top exposes
# the bus as ordinary ports: it is a real AHB master, but IPI's inference does
# not recognise AHB from port names the way it does AXI.
proc amoeba_connect_ahb {dut br} {
    set map {
        m_ahb_hsel      s_ahb_hsel
        m_ahb_haddr     s_ahb_haddr
        m_ahb_hwdata    s_ahb_hwdata
        m_ahb_hwrite    s_ahb_hwrite
        m_ahb_hsize     s_ahb_hsize
        m_ahb_hburst    s_ahb_hburst
        m_ahb_hprot     s_ahb_hprot
        m_ahb_htrans    s_ahb_htrans
        m_ahb_hmastlock s_ahb_hmastlock
        m_ahb_hrdata    s_ahb_hrdata
        m_ahb_hready    s_ahb_hreadyout
        m_ahb_hresp     s_ahb_hresp
    }
    foreach {a b} $map {
        set pa [get_bd_pins -quiet $dut/$a]
        set pb [get_bd_pins -quiet $br/$b]
        if {[llength $pa] && [llength $pb]} {
            connect_bd_net $pa $pb
        } else {
            puts "WARNING: could not connect $dut/$a to $br/$b"
        }
    }
}
