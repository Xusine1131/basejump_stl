decoder:
	make clean
	verilator --Wno-fatal -I../../../bsg_misc/ \
	-I../../../bsg_fpu/ \
	-sv --cc \
	../../../bsg_misc/bsg_defines.v \
	../../../bsg_fpu/bsg_fpu_pkg.v \
	../../../bsg_fpu/bsg_fpu_clz.v \
	../../../bsg_fpu/bsg_fpu_decoder.v \
	-Ge_p=8 -Gm_p=23 \
	--top-module bsg_fpu_decoder \
	--exe ./decoder.cpp \
	-CFLAGS "-g -std=c++11" 

	make -C obj_dir -f Vbsg_fpu_decoder.mk

	./obj_dir/Vbsg_fpu_decoder


encoder:
	make clean
	verilator --Wno-fatal -I../../../bsg_misc/ \
	-I../../../bsg_fpu/ \
	-sv --cc \
	../../../bsg_misc/bsg_defines.v \
	../../../bsg_fpu/bsg_fpu_pkg.v \
	../../../bsg_fpu/bsg_fpu_encoder.v \
	--top-module bsg_fpu_encoder \
	-Ge_p=8 -Gm_p=23 \
	--exe ./encoder.cpp \
	-CFLAGS "-g -std=c++11" 

	make -C obj_dir -f Vbsg_fpu_encoder.mk

	./obj_dir/Vbsg_fpu_encoder

clean:
	@rm -rf obj_dir