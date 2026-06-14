SIM ?= verilator
TOPLEVEL_LANG = verilog

PROJECT_ROOT := $(abspath ../../..)

VERILOG_SOURCES = \
	$(PROJECT_ROOT)/ip/crossbar/logic/crossbar.sv

TOPLEVEL = crossbar
COCOTB_TEST_MODULES = test_crossbar

EXTRA_ARGS += --timing
EXTRA_ARGS += --assert
EXTRA_ARGS += -GADDR_WIDTH=32
EXTRA_ARGS += -GDATA_WIDTH=32
EXTRA_ARGS += -GID_WIDTH=4
EXTRA_ARGS += -GAXI_BASE_ADDR=0
EXTRA_ARGS += -GAXI_ADDR_MASK=4026531840
EXTRA_ARGS += -GAPB_BASE_ADDR=268435456
EXTRA_ARGS += -GAPB_ADDR_MASK=4026531840

export PYTHONPATH := $(PROJECT_ROOT):$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
