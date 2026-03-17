#include "raven.hlsli"

RESOURCE_SLOT(2, Texture2DArray tex);
SAMPLER_SLOT(0, SamplerState smp);

float4 ps_main(VS_Out input, uint frontface : SV_IsFrontFace) : SV_Target {
    float3 normal = normalize(bool(frontface) ? input.normal : -input.normal);
    float4 col = input.add_col + input.col * tex.Sample(smp, float3(input.uv, float(input.tex_slice)));

    if (col.a < 0.001) {
        discard;
    }

    return col;
}
