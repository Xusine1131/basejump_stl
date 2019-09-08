int sign_extend(int value, int pos){
    int sign_bits_mask = 1 << pos;
    int sign_bits = value & sign_bits_mask;
    if(sign_bits){
        sign_bits_mask <<= 1;
        sign_bits_mask -= 1;
        sign_bits_mask ^= 0xFFFFFFFF;
        value |= sign_bits_mask;
        return value;
    } else {
        return value;
    }
}

float i2f(int value){
    float *res = (float *)&value;
    return *res;
}

int f2i(float value){
    int *res = (int *)&value;
    return *res;
}

long long int d2i(double value){
    long long int *res = (long long int *)&value;
    return *res;
}