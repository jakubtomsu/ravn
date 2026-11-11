#include "common.slang"

float4 ps_main(VS_Out vert) : SV_Target {
    return vert.col;
}
