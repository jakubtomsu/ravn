#include "common.slang"

float4 ps_main(Vert_Out input) : SV_Target {
    float4 out_col = input.col * params.tex.Sample(params.smp, input.uv);
    return out_col;
}
