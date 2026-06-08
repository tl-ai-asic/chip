SIM ?= verilator
TOPLEVEL_LANG = verilog

PROJECT_ROOT := $(abspath ../../..)

VERILOG_SOURCES = \
	$(PROJECT_ROOT)/ip/lru_cache/logic/lru_cache.sv

TOPLEVEL = lru_cache
COCOTB_TEST_MODULES = test_lru_cache

EXTRA_ARGS += --timing
EXTRA_ARGS += --assert
EXTRA_ARGS += -GADDR_WIDTH=16
EXTRA_ARGS += -GDATA_WIDTH=32
EXTRA_ARGS += -GSET_COUNT=2
EXTRA_ARGS += -GWAY_COUNT=2

export PYTHONPATH := $(PROJECT_ROOT):$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
