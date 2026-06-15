SIM ?= verilator
TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

PROJECT_ROOT := $(abspath ../../../..)
IP_ROOT := $(abspath ..)

VERILOG_SOURCES = \
	$(IP_ROOT)/logic/riscv32im_scoreboard_types.sv \
	$(IP_ROOT)/logic/riscv32im_alu.sv \
	$(IP_ROOT)/logic/riscv32im_muldiv.sv \
	$(IP_ROOT)/logic/riscv32im_decode.sv \
	$(IP_ROOT)/logic/riscv32im_prefetch.sv \
	$(IP_ROOT)/logic/riscv32im_csr_read.sv \
	$(IP_ROOT)/logic/riscv32im_csr_file.sv \
	$(IP_ROOT)/logic/riscv32im_issue_prepare.sv \
	$(IP_ROOT)/logic/riscv32im_alu_execute.sv \
	$(IP_ROOT)/logic/riscv32im_lsu_format.sv \
	$(IP_ROOT)/logic/riscv32im_lsu.sv \
	$(IP_ROOT)/logic/riscv32im_scoreboard.sv \
	$(IP_ROOT)/logic/riscv32im_rvfi_trace.sv \
	$(IP_ROOT)/logic/riscv32im_core.sv

TOPLEVEL = riscv32im_core
COCOTB_TEST_MODULES = test_riscv32im_core

RESET_VECTOR ?= 0x80000000
RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_TESTS_ROOT ?= $(HOME)/tools/riscv/src/riscv-tests
RISCV_TEST_BUILD ?= /tmp/riscv32imc_v4_riscv_tests
RISCV_BENCH_ROOT ?= $(PROJECT_ROOT)/ip/riscv/benchmarks
RISCV_BENCH_BUILD ?= /tmp/riscv32imc_ipc_benchmarks
RISCV_TIMEOUT_CYCLES ?= 1000000
CORE_VERSION = v4
EXPECT_LSU_PARALLEL = 1

EXTRA_ARGS += --timing
EXTRA_ARGS += --assert
EXTRA_ARGS += --coverage-user
EXTRA_ARGS += -GRESET_VECTOR=$(RESET_VECTOR)

export PYTHONPATH := $(PROJECT_ROOT):$(PYTHONPATH)
export RESET_VECTOR
export CORE_VERSION
export EXPECT_LSU_PARALLEL
export RISCV_BINARY
export RISCV_BINARIES
export RISCV_BINARY_BASE
export RISCV_TIMEOUT_CYCLES
export RISCV_TOHOST
export IPC_BINARY_DIR

.PHONY: build-riscv-tests build-ipc-tests run-riscv-tests run-ipc-tests

run-ipc-tests: build-ipc-tests
	$(MAKE) sim COCOTB_TEST_FILTER='test_ipc_.*' IPC_BINARY_DIR=$(RISCV_BENCH_BUILD)

build-ipc-tests:
	mkdir -p $(RISCV_BENCH_BUILD)
	for srcfile in $(RISCV_BENCH_ROOT)/ipc_*.S; do \
	  name=$$(basename $$srcfile .S); \
	  out=$(RISCV_BENCH_BUILD)/$$name; \
	  $(RISCV_GCC) \
	    -march=rv32im -mabi=ilp32 \
	    -static -nostdlib -nostartfiles \
	    -T$(RISCV_BENCH_ROOT)/link.ld \
	    $$srcfile -o $$out; \
	  $(RISCV_OBJDUMP) \
	    --disassemble-all --disassemble-zeroes \
	    --section=.text.init --section=.tohost --section=.data \
	    $$out > $$out.dump; \
	done

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

run-riscv-tests: build-riscv-tests build-ipc-tests
	TESTS=$$(find $(RISCV_TEST_BUILD) -maxdepth 1 -type f ! -name '*.dump' | sort | tr '\n' ' '); \
	$(MAKE) sim RISCV_BINARIES="$$TESTS" RISCV_TIMEOUT_CYCLES=$(RISCV_TIMEOUT_CYCLES) IPC_BINARY_DIR=$(RISCV_BENCH_BUILD)

include $(shell cocotb-config --makefiles)/Makefile.sim
