#pragma once

struct Vert_In {
    float2 pos : TEXCOORD0;
    float2 uv  : TEXCOORD1;
    float4 col : TEXCOORD2;
};

struct Vert_Out {
    float4 pos : SV_Position;
    float4 col : COLOR0;
    float2 uv  : TEXCOORD0;
};

struct Params {
    float4x4 proj;
    Texture2D tex;
    SamplerState smp;
};

ParameterBlock<Params> params;