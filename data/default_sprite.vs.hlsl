#include "raven.hlsli"

RV_RESOURCE_SLOT(0, StructuredBuffer<RV_Sprite_Inst_Packed> instances);

RV_Varyings vs_main(uint vid : SV_VertexID, uint inst_id : SV_InstanceID) {
    RV_Sprite_Inst inst = rv_unpack_sprite_inst(instances[inst_id + rv_instance_offset]);

    float2 local_uv = float2(float(vid & 1), float(vid / 2));

    float2 local_pos = local_uv * 2.0 - 1.0;

    RV_Varyings vars;
    float3 world_pos = inst.pos  + inst.mat_x * local_pos.x + inst.mat_y * local_pos.y;
    vars.pos = mul(rv_view_proj, float4(world_pos, 1.0f));
    vars.world_pos = world_pos;
    vars.normal = cross(inst.mat_x, inst.mat_y);
    vars.uv = inst.uv_min + inst.uv_size * local_uv;
    vars.col = inst.col;
    vars.add_col = inst.add_col;
    vars.tex_slice = inst.tex_slice;

    return vars;
}
