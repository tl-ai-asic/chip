SIM ?= verilator
TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

PROJECT_ROOT := $(abspath ../../..)
CORE_VERSION ?= v3
LOGIC_DIR := $(PROJECT_ROOT)/ip/riscv32im_core/logic_$(CORE_VERSION)

ifeq ($(CORE_VERSION),v1)
VERILOG_SOURCES = \
	$(LOGIC_DIR)/riscv32im_alu.sv \
	$(LOGIC_DIR)/riscv32im_muldiv.sv \
	$(LOGIC_DIR)/riscv32im_decode.sv \
	$(LOGIC_DIR)/riscv32im_csr_read.sv \
	$(LOGIC_DIR)/riscv32im_lsu_format.sv \
	$(LOGIC_DIR)/riscv32im_lsu.sv \
	$(LOGIC_DIR)/riscv32im_core.sv
else

VERILOG_SOURCES = \
	$(LOGIC_DIR)/riscv32im_scoreboard_types.sv \
	$(LOGIC_DIR)/riscv32im_alu.sv \
	$(LOGIC_DIR)/riscv32im_muldiv.sv \
	$(LOGIC_DIR)/riscv32im_decode.sv \
	$(LOGIC_DIR)/riscv32im_csr_read.sv \
	$(LOGIC_DIR)/riscv32im_csr_file.sv \
	$(LOGIC_DIR)/riscv32im_issue_prepare.sv \
	$(LOGIC_DIR)/riscv32im_alu_execute.sv \
	$(LOGIC_DIR)/riscv32im_lsu_format.sv \
	$(LOGIC_DIR)/riscv32im_lsu.sv \
	$(LOGIC_DIR)/riscv32im_scoreboard.sv \
	$(LOGIC_DIR)/riscv32im_rvfi_trace.sv \
	$(LOGIC_DIR)/riscv32im_core.sv
endif

TOPLEVEL = riscv32im_core
COCOTB_TEST_MODULES = test_riscv32im_core

RESET_VECTOR ?= 0x80000000
RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_TESTS_ROOT ?= $(HOME)/tools/riscv/src/riscv-tests
RISCV_TEST_BUILD ?= /tmp/riscv32im_core_riscv_tests
RISCV_TIMEOUT_CYCLES ?= 1000000

EXTRA_ARGS += --timing
EXTRA_ARGS += --assert
EXTRA_ARGS += --coverage-user
EXTRA_ARGS += -GRESET_VECTOR=$(RESET_VECTOR)

export PYTHONPATH := $(PROJECT_ROOT):$(PYTHONPATH)
export RESET_VECTOR
export CORE_VERSION
export RISCV_BINARY
export RISCV_BINARIES
export RISCV_BINARY_BASE
export RISCV_TIMEOUT_CYCLES
export RISCV_TOHOST

.PHONY: build-riscv-tests run-riscv-tests

build-riscv-tests:
	mkdir -p $(RISCV_TEST_BUILD)
	for suite in rv32ui rv32um; do \
	  for srcfile in $(RISCV_TESTS_ROOT)/isa/$$suite/*.S; do \
	    name=$$(basename $$srcfile .S); \
	    out=$(RISCV_TEST_BUILD)/$$suite-p-$$name; \
	    $(RISCV_GCC) \
	      -march=rv32g -mabi=ilp32 \
	      -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
	      -I$(RISCV_TESTS_ROOT)/env/p \
	      -I$(RISCV_TESTS_ROOT)/isa/macros/scalar \
	      -T$(RISCV_TESTS_ROOT)/env/p/link.ld \
	      $$srcfile -o $$out; \
	    $(RISCV_OBJDUMP) \
	      --disassemble-all --disassemble-zeroes \
	      --section=.text --section=.text.startup --section=.text.init --section=.data \
	      $$out > $$out.dump; \
	  done; \
	done

run-riscv-tests: build-riscv-tests
	TESTS=$$(find $(RISCV_TEST_BUILD) -maxdepth 1 -type f ! -name '*.dump' | sort | tr '\n' ' '); \
	$(MAKE) sim RISCV_BINARIES="$$TESTS" RISCV_TIMEOUT_CYCLES=$(RISCV_TIMEOUT_CYCLES)

include $(shell cocotb-config --makefiles)/Makefile.sim
