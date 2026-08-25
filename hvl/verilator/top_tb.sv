module top_tb
(
    input   logic   clk,
    input   logic   rst,
    output  logic   dump_on
);

    // Waveform dumping is compiled out entirely for the Linux boot tier.  The
    // plusarg-driven $dumpoff() below does NOT stop Verilator from writing the
    // FST -- a boot-length run produces hundreds of GB and costs ~50x in wall
    // time -- so the only reliable way to disable it is at compile time.
`ifndef ECE411_NO_TRACE
    initial begin
        $dumpfile("dump.fst");
        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $dumpvars(0, dut);
            $dumpoff();
        end else begin
            $dumpvars();
        end
    end
`endif

    assign dump_on = monitor.dump_on;

    `include "top_tb.svh"

endmodule
