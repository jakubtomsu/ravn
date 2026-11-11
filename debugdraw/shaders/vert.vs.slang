#include "common.slang"

struct Vert {
    float3 pos : TEXCOORD0;
    float4 col : TEXCOORD1;
};

cbuffer constants {
    float4x4 proj;
};

VS_Out vs_main(Vert vert) {
    VS_Out o;
    o.pos = mul(proj, float4(vert.pos.xyz, 1.0f));
    o.col = vert.col;
    return o;
}