BASEJUMP_STL_DIR=$(PWD)/../../../..

BSG_MULTIPLIER_COMPRESSOR=$(BASEJUMP_STL_DIR)/bsg_misc/bsg_multiplier_compressor

VERILOG_SOURCES=$(PWD)/timescale.v $(BASEJUMP_STL_DIR)/bsg_misc/bsg_defines.v $(BASEJUMP_STL_DIR)/bsg_misc/bsg_mul_iterative.v $(BASEJUMP_STL_DIR)/bsg_misc/bsg_adder_carry_save.v $(BSG_MULTIPLIER_COMPRESSOR)/bsg_multiplier_compressor_64_32_4.v

TOPLEVEL=bsg_mul_iterative
MODULE=test_bsg

SIM=vcs

VCS_OPTIONS=-full64 -cc gcc-4.9 -cpp g++-4.9

COMPILE_ARGS = $(VCS_OPTIONS) -sverilog

include $(shell cocotb-config --makefiles)/Makefile.inc
include $(shell cocotb-config --makefiles)/Makefile.sim