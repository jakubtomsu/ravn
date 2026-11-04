#ifndef DEBUGDRAW_COMMON_HLSLI_INCLUDED
#define DEBUGDRAW_COMMON_HLSLI_INCLUDED

struct VS_Out {
    float4 pos : SV_Position;
    float4 col : TEXCOORD0;
};

#endif