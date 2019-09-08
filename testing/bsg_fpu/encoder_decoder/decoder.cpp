#include "obj_dir/Vbsg_fpu_decoder.h"
#include "aux.hpp"
#include "verilated.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <ctime>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vbsg_fpu_decoder *decoder = new Vbsg_fpu_decoder{};

    // initialize
    decoder->a_i = 0;
    decoder->eval();

    std::srand(std::time(NULL));
    
    // subnormal conditions
    for(int i = 0; i < 50000; ++i){
        int testing = rand() & 0x7FFFFF;
        decoder->a_i = testing;
        decoder->eval();
        int man = decoder->man_o;
        int exp = sign_extend(decoder->exp_o, 8);
        float value = float(man)  * std::pow(2.0, exp - 127 - 23);
        float expected = i2f(testing);
        if(value != expected){
            std::printf("value = %f, expected = %f, dismatch!\n", value, expected);
            return 1;
        }
    }
    // normal conditions
    for(int i = 0; i < 10; ++i){
        int testing = rand() + 0x800000;
        decoder->a_i = testing;
        decoder->eval();
        int man = decoder->man_o;
        int exp = sign_extend(decoder->exp_o, 8);
        float value = float(man)  * std::pow(2.0, exp - 127 - 23);
        float expected = i2f(testing);
        if(value != expected){
            std::printf("value = %f, expected = %f, dismatch!\n", value, expected);
            return 1;
        }
    }
    return 0;
}


