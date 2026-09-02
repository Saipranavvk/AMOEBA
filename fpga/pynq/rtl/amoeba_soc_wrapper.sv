///////////////////////////////////////////////////////////////////////////////
// amoeba_soc_wrapper.sv
//
// Synthesis top for the FPGA build, and the module the utilization gate
// measures.
//
// This is deliberately NOT hdl/rv64_core_wrapper.sv.  That wrapper exposes
// several hundred monitor_* ports so the testbench can watch every retired
// instruction; at a pin boundary those ports are preserved by synthesis, which
// keeps the whole RVFI tap pipeline alive and inflates the area report with
// logic no FPGA bitstream would ever contain.  The two wrappers instantiate the
// same hardware and are meant to stay separate.
//
// What is inside, at CONFIG=baremetal_linux:
//
//   wallypipelinedcore   <- the tapeout
//   adrdecs              <- address decode, drives HSELEXT
//   ahbapbbridge         <- 105 lines
//   clint_apb            <- mandatory: the core takes MTimerInt/MSwInt/MTIME
//                           as INPUTS, and nothing generates them without it
//   uart_apb             <- the console
//
// PLIC, GPIO, SPI, SDC, BootROM and the uncore RAM are all _SUPPORTED = 0 in
// the pruned configs and generate away, so instantiating wallypipelinedsoc
// costs nothing over hand-rolling the scaffolding -- and it is already
// exercised by every simulation tier.
//
// The AHB master leaves this module unflattened, on purpose.  The bring-up
// bitstream feeds it to hdl/ahb_to_memitf.sv and a block RAM; the production
// bitstream hands it straight to Xilinx's ahblite_axi_bridge so that 8-beat
// cache-line fills stay bursts all the way to the HP port.  Converting to the
// mem_itf protocol first would flatten those into eight single transfers,
// which is free against block RAM and roughly 7x against DDR.
///////////////////////////////////////////////////////////////////////////////

// The config must be included at file scope, before the module: the port list
// below uses PA_BITS, AHBW and XLEN, which it defines.  Behind a guard because
// amoeba_pynq_top needs the same declarations at the same scope and the two are
// compiled together.
`include "amoeba_config_select.vh"

module amoeba_soc_wrapper import cvw::*; (
    input  logic                  clk,
    input  logic                  reset_ext,   // async; the SoC synchronizes it
    output logic                  reset,       // synchronized reset, back out

    // Debug / stimulus control.  Held low today; amoeba_trace drives it once
    // the commit-trace FIFO exists, so the core stalls rather than dropping
    // commits when the PS cannot keep up.  Folded into StallWCause by
    // hdl/core/hazard/hazard.sv.
    input  logic                  ExternalStall,

    // AHB-Lite master, to the memory backend
    input  logic [AHBW-1:0]       HRDATAEXT,
    input  logic                  HREADYEXT,
    input  logic                  HRESPEXT,
    output logic                  HSELEXT,
    output logic                  HCLK,
    output logic                  HRESETn,
    output logic [PA_BITS-1:0]    HADDR,
    output logic [AHBW-1:0]       HWDATA,
    output logic [XLEN/8-1:0]     HWSTRB,
    output logic                  HWRITE,
    output logic [2:0]            HSIZE,
    output logic [2:0]            HBURST,
    output logic [3:0]            HPROT,
    output logic [1:0]            HTRANS,
    output logic                  HMASTLOCK,
    output logic                  HREADY,

    // Console.  UARTSout is kept as a real pin so the NS16550 is not optimized
    // away -- the PL bus monitor takes the byte by snooping the AHB write to
    // the transmit register, but the peripheral itself has to stay for its
    // LSR/THRE semantics, which is what stops the 8250 driver spinning.
    input  logic                  UARTSin,
    output logic                  UARTSout
);

    `include "parameter-defs.vh"

    wallypipelinedsoc #(P) soc (
        .clk           (clk),
        .reset_ext     (reset_ext),
        .reset         (reset),
        .ExternalStall (ExternalStall),

        .HRDATAEXT     (HRDATAEXT),
        .HREADYEXT     (HREADYEXT),
        .HRESPEXT      (HRESPEXT),
        .HSELEXT       (HSELEXT),

        .HCLK          (HCLK),
        .HRESETn       (HRESETn),
        .HADDR         (HADDR),
        .HWDATA        (HWDATA),
        .HWSTRB        (HWSTRB),
        .HWRITE        (HWRITE),
        .HSIZE         (HSIZE),
        .HBURST        (HBURST),
        .HPROT         (HPROT),
        .HTRANS        (HTRANS),
        .HMASTLOCK     (HMASTLOCK),
        .HREADY        (HREADY),

        // CLINT drives MTIME off HCLK: TIMECLK is tied low here exactly as it
        // is in hdl/rv64_core_wrapper.sv, so the CLINT tick rate equals the
        // system clock.  The Linux device tree's timebase-frequency and
        // FreeRTOS's configCPU_CLOCK_HZ both have to match whatever FCLK_CLK0
        // ends up being -- on FPGA that is not the 100 MHz the sim uses.
        .TIMECLK       (1'b0),

        .GPIOIN        (32'h0),
        .GPIOOUT       (),
        .GPIOEN        (),

        .UARTSin       (UARTSin),
        .UARTSout      (UARTSout),

        // Not present at any pruned config (_SUPPORTED = 0); tied off so the
        // ports resolve and nothing reaches a pin.
        .SPIIn         (1'b0),
        .SPIOut        (),
        .SPICS         (),
        .SPICLK        (),
        .SDCIn         (1'b0),
        .SDCCmd        (),
        .SDCCS         (),
        .SDCCLK        ()
    );

endmodule
