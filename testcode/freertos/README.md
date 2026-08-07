# FreeRTOS Test

FreeRTOS build infrastructure will be added in Phase 5 of the migration plan.

Currently `sorting_algo_app.c` defines `void app_main(void)` which will be called
by a `freertos_main.c` harness once the FreeRTOS-Kernel submodule and linker script
are in place.

See `PLAN.md` Phase 5 for details.
