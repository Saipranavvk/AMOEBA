SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

export PKG_SRCS = $(PWD)/../pkg/types.sv
CVW_SRCS       := $(shell find $(PWD)/../hdl/cvw/src -name '*.sv' -o -name '*.v' 2>/dev/null)
LEGACY         := $(PWD)/../hdl/cpu.sv $(PWD)/../hdl/regfile.sv $(PWD)/../hdl/provided_cache.sv
export HDL_SRCS = $(filter-out $(PWD)/../hdl/cvw/% $(LEGACY), $(shell find $(PWD)/../hdl -name '*.sv')) $(CVW_SRCS)
export SRAM_LIB = $(shell find $(PWD)/../sram/output/ -name "*.db")
export DESIGN_TOP = cvw_rvfi_wrapper

.PHONY: lint
lint: clean
	mkdir -p reports
	sg_shell -licqueue < lint.tcl |& tee reports/lint.log
	mv spyglass-1/consolidated_reports/*_lint_lint_turbo_rtl/*.rpt reports/
	mv reports/moresimple_turbo.rpt reports/lint.rpt
	rm -rf spyglass-1 WORK *.log
	bash check_lint_error.sh

.PHONY: clean
clean:
	rm -rf spyglass-1 WORK *.log reports
