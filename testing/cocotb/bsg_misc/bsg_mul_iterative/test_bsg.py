import cocotb
from cocotb.triggers import Timer

import random

@cocotb.coroutine
async def tick(dut):
    dut.clk_i <= 1
    await Timer(1, units="ns")
    dut.clk_i <= 0
    await Timer(1, units="ns")

@cocotb.test()
async def random_test(dut):
    dut.clk_i = 0
    dut.reset_i = 0
    dut.opA_i = 0
    dut.opB_i = 0
    dut.signed_i = 0
    dut.v_i = 0
    dut.yumi_i = 1
    await Timer(1, units="ns")

    # reset
    dut.reset_i = 1
    await Timer(1, units="ns")
    dut.clk_i = 1
    await Timer(1, units="ns")
    dut.reset_i = 0
    dut.clk_i = 0
    await Timer(1, units="ns")

    # Random Test
    for _ in range(1000):

        dut.signed_i = random.randint(0,1)

        opA = random.randint(0,0xFFFFFFFFFFFFFFFF)
        opB = random.randint(0,0xFFFFFFFFFFFFFFFF)
    

        dut.opA_i = opA
        dut.opB_i = opB

        dut.v_i = 1
        await Timer(1, units="ns")

        if dut.signed_i == 1:
            if (opA & (0x1 << 63)) != 0:
                opA -= (0x1 << 64)
            if (opB & (0x1 << 63)) != 0:
                opB -= (0x1 << 64)

        dut.clk_i = 1
        await Timer(1, units="ns")

        dut.v_i = 0
        dut.clk_i = 0
        await Timer(1, units="ns")

        while dut.v_o == 0:
            await tick(dut)
        
        # print(dut.v_o)
        await Timer(1, units="ns")
        # print(dut.v_o)
        res = int(dut.result_o)
        await tick(dut)

        if dut.signed_i != 0 and (res & 0x1 << 127) != 0:
            res -= (0x1 << 128)


        if res != opA * opB:
        #if True:
            print(dut.signed_i)
            print(int(res))
            print(opA)
            print(opB)
            print(opA * opB)
            dut._log.error("Mismatched result!")
            return


    dut.signed_i = 1
    await Timer(1, units="ns")

    dut._log.info("Pass!")
            
    

