///////////////////////////////////////////
// csrharden.sv
//
// Purpose: Combinational CSR hardening fault aggregator.
//          Collects integrity violation signals from across the privileged
//          unit and presents them as a one-hot fault bus for MSECFAULT.
//
// MSECFAULT bit map:
//   [0] PrivilegeModeW TMR correctable fault (2+ copies agree, 1 corrupted)
//   [1] STATUS_MPP reserved encoding (2'b10) detected in register
//   [2] Illegal CSR access (wrong privilege level or nonexistent address)
//   [3] PrivilegeModeW TMR uncorrectable fault (no majority consensus)
//   [6:4] Reserved, hardwired 0
//
// A component of the AMOEBA RV64GC project.
////////////////////////////////////////////////////////////////////////////////////////////////

module csrharden (
  input  logic       PrivModeSecFaultW,           // from privmode: TMR correctable fault
  input  logic       PrivModeUncorrectableFaultW, // from privmode: TMR uncorrectable fault
  input  logic       MppReservedM,                // STATUS_MPP == 2'b10
  input  logic       IllegalCSRAccessM,           // illegal CSR access from csr
  input  logic       InstrValidM,                 // gate fault on flushed instructions
  output logic [6:0] SecFaultM                    // one-hot fault causes to MSECFAULT register
);

  assign SecFaultM[0]   = PrivModeSecFaultW;
  assign SecFaultM[1]   = MppReservedM;
  assign SecFaultM[2]   = IllegalCSRAccessM & InstrValidM;
  assign SecFaultM[3]   = PrivModeUncorrectableFaultW;
  assign SecFaultM[6:4] = 3'b000;

endmodule
