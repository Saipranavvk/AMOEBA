///////////////////////////////////////////////////////////////////////////////
// amoeba_config_select.vh
//
// Selects which configuration a synthesis or simulation top elaborates.  The
// config files declare their parameters at compilation-unit scope, so more than
// one top including the ladder directly collides on every localparam once those
// tops are compiled together -- which is exactly what happens when the FPGA
// build elaborates amoeba_pynq_top and pulls amoeba_soc_wrapper in with it.
// Hence one ladder, behind one guard.
//
//   AMOEBA_CONFIG_FREERTOS           pkg/config_freertos.vh
//                                    pruned to what the FreeRTOS tier executes
//   AMOEBA_CONFIG_FREERTOS_KEYSTONE  pkg/config_freertos_keystone.vh
//                                    that set plus OpenSBI and the Keystone SM
//   AMOEBA_CONFIG_BAREMETAL_LINUX    pkg/config_baremetal_linux.vh
//                                    the smallest core that boots a soft-float
//                                    Linux; this is the tapeout config
//   (none)                           pkg/config.vh -- the full RV64GC core
///////////////////////////////////////////////////////////////////////////////
`ifndef AMOEBA_CONFIG_SELECT_VH
`define AMOEBA_CONFIG_SELECT_VH

`ifdef AMOEBA_CONFIG_FREERTOS
`include "config_freertos.vh"
`elsif AMOEBA_CONFIG_FREERTOS_KEYSTONE
`include "config_freertos_keystone.vh"
`elsif AMOEBA_CONFIG_BAREMETAL_LINUX
`include "config_baremetal_linux.vh"
`else
`include "config.vh"
`endif

`endif
