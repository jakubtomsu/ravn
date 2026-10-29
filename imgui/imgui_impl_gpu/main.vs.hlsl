cbuffer vertexBuffer : register(b0) {
    float4x4 proj;
};

struct VS_INPUT {
    float2 pos : TEXCOORD0;
    float2 uv  : TEXCOORD1;
    float4 col : TEXCOORD2;
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float4 col : COLOR0;
    float2 uv  : TEXCOORD0;
};

PS_INPUT vs_main(VS_INPUT vert) {
    PS_INPUT o;
    o.pos = mul(proj, float4(vert.pos.xy, 0.0f, 1.0f));
    o.col = vert.col;
    o.uv  = vert.uv;
    return o;
}