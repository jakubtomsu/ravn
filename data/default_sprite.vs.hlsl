#include "raven.hlsli"

RESOURCE_SLOT(0, StructuredBuffer<Sprite_Inst> instances);

VS_Out vs_main(uint vid : SV_VertexID, uint inst_id : SV_InstanceID) {
    Sprite_Inst inst = instances[inst_id + instance_offset];

    float2 local_uv = float2(float(vid & 1), float(vid / 2));

    float2 local_pos = local_uv * 2.0 - 1.0;
    float2 uv_min = unpack_uv_unorm16(inst.uv_min);
    float2 uv_size = unpack_uv_unorm16(inst.uv_size);

    VS_Out o;
    float3 world_pos = inst.pos  + inst.mat_x * local_pos.x + inst.mat_y * local_pos.y;
    o.pos = mul(view_proj, float4(world_pos, 1.0f));
    o.world_pos = world_pos;
    o.normal = cross(inst.mat_x, inst.mat_y);
    o.uv = uv_min + uv_size * local_uv;
    // o.uv = local_uv;
    o.col = unpack_signed_color_unorm8(inst.col);
    o.add_col = unpack_signed_color_unorm8(inst.add_col);
    o.tex_slice = inst.tex_slice;

    return o;
}
