#include "ravn.hlsli"

RV_RESOURCE_SLOT(0, Texture2D<float4> src);
RV_RW_RESOURCE_SLOT(0, RWTexture2D<float4> dst);

[numthreads(8, 8, 1)]
void cs_main(int3 did : SV_DispatchThreadID) {
    float curr = src[did.xy].r;
    int neighbors = 0;
    neighbors += src[did.xy + int2(-1, -1)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2( 0, -1)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2( 1, -1)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2(-1,  0)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2( 1,  0)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2(-1,  1)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2( 0,  1)].r > 0 ? 1 : 0;
    neighbors += src[did.xy + int2( 1,  1)].r > 0 ? 1 : 0;

    if (curr > 0.5) {
        if (neighbors < 2 || neighbors > 3) {
            curr = 0.0f;
        }
    } else {
        if (neighbors == 3) {
            curr = 1.0f;
        }
    }

    dst[did.xy] = curr.xxxx;
}