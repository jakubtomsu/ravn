#include "common.slang"

struct Vert {
    float4 pos : TEXCOORD0;
    float4 inst_pos : TEXCOORD1;
    float4 inst_col : TEXCOORD2;
    float4 inst_mat_x : TEXCOORD3;
    float4 inst_mat_y : TEXCOORD4;
    float4 inst_mat_z : TEXCOORD5;
};

cbuffer constants {
    float4x4 proj;
};

VS_Out vs_main(Vert vert) {
    VS_Out o;
    float3 pos = vert.inst_pos.xyz +
        vert.pos.x * vert.inst_mat_x.xyz +
        vert.pos.y * vert.inst_mat_y.xyz +
        vert.pos.z * vert.inst_mat_z.xyz;
    o.pos = mul(proj, float4(pos, 1.0f));
    o.col = vert.inst_col;
    return o;
}