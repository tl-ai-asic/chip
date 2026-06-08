SIM ?= verilator
TOPLEVEL_LANG = verilog

PROJECT_ROOT := $(abspath ../../..)

VERILOG_SOURCES = \
	$(PROJECT_ROOT)/ip/dma/logic/dma_id_pool.sv \
	$(PROJECT_ROOT)/ip/dma/logic/dma_reorder_buffer.sv \
	$(PROJECT_ROOT)/ip/dma/logic/dma.sv

TOPLEVEL = dma
COCOTB_TEST_MODULES = test_dma

EXTRA_ARGS += --timing
EXTRA_ARGS += --assert
EXTRA_ARGS += --coverage-user
EXTRA_ARGS += -GADDR_WIDTH=16
EXTRA_ARGS += -GDATA_WIDTH=32
EXTRA_ARGS += -GMAX_OUTSTANDING_READS=4
EXTRA_ARGS += -GMAX_OUTSTANDING_WRITES=3
EXTRA_ARGS += -GMAX_TRANSFER_WORDS=4096

export PYTHONPATH := $(PROJECT_ROOT):$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
