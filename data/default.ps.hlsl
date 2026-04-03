#include "raven.hlsli"

RV_RESOURCE_SLOT(2, Texture2DArray tex);
RV_SAMPLER_SLOT(0, SamplerState smp);

float4 ps_main(RV_Varyings vars, uint frontface : SV_IsFrontFace) : SV_Target {
    float3 normal = normalize(bool(frontface) ? vars.normal : -vars.normal);
    float4 col = vars.add_col + vars.col * tex.Sample(smp, float3(vars.uv, float(vars.tex_slice)));

    // TODO: shader variants to not have this in every PS
    if (col.a < 0.001) {
        discard;
    }

    return col;
}
