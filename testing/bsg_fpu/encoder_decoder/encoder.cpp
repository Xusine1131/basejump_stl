#include "obj_dir/Vbsg_fpu_encoder.h"
#include "aux.hpp"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cmath>

int main(int argc, char **argv){
    Verilated::commandArgs(argc, argv);

    Vbsg_fpu_encoder *encoder = new Vbsg_fpu_encoder;

    encoder->exp_i = 0;
    encoder->mantissa_i = 0;
    encoder->sign_i = 0;
    encoder->exp_i = 0;

    encoder->is_invalid_i = 0;
    encoder->is_overflow_i = 0;
    encoder->is_underflow_i = 0;

    encoder->eval();

    int error = 0;

    for(int i = 0; i < 50000; ++i){
        // generate mantissa.
        int mantissa = rand() & 0x7FFFFF;
        mantissa |= 0x800000;
        // generat exponent 
        int exponent = rand() & 0x1FF;

        int sign = rand() & 0x1;

        encoder->exp_i = exponent;
        encoder->mantissa_i = mantissa;
        encoder->sign_i = sign;

        encoder->eval();
        float res = i2f(encoder->o);

        // calculate float according to the generate parameters.
        float mantissa_f = float(mantissa);
        float expected = mantissa_f * std::pow(2.0, sign_extend(exponent, 8) - 127 - 23);
        if (sign) expected = -expected;

        if(res != expected){
            std::printf("Error! output:%f(%x), expected:%f(%x) mantissa:%d(%x) mantissa_f:%f(%x) exp:%d(%x) before_round_mantissa:%x\n", res, encoder->o, expected, f2i(expected), mantissa, mantissa, mantissa_f, f2i(mantissa_f), sign_extend(exponent,8), exponent, encoder->bsg_fpu_encoder__DOT__before_round_mantissa);
            //return 1;
            ++error;
        }
    }

    std::printf("Done, error:%d\n", error);

    return 0;
}
