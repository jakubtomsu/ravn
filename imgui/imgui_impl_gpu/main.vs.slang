#include "common.slang"

Vert_Out vs_main(Vert_In vert) {
    Vert_Out o;
    o.pos = mul(params.proj, float4(vert.pos.xy, 0.0f, 1.0f));
    o.col = vert.col;
    o.uv  = vert.uv;
    return o;
}