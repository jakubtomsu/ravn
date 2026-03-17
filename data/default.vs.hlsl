#include "raven.hlsli"

RESOURCE_SLOT(0, StructuredBuffer<Mesh_Inst> instances);
RESOURCE_SLOT(1, StructuredBuffer<Vertex> verts);

VS_Out vs_main(uint vid : SV_VertexID, uint inst_id : SV_InstanceID) {
    Mesh_Inst inst = instances[inst_id + instance_offset];
    uint vert_offs = inst.tex_slice_vert_offs >> 8;
    Vertex vert = verts[vid + vert_offs];

    float3x3 mat = float3x3(inst.mat_x, inst.mat_y, inst.mat_z);

    VS_Out o;
    float3 world_pos = inst.pos + mul(vert.pos, mat);
    o.pos = mul(view_proj, float4(world_pos, 1.0f));
    o.world_pos = world_pos;
    o.normal = unpack_unorm8(vert.normal).xyz; // * adjugate
    o.uv = vert.uv;
    o.col = unpack_signed_color_unorm8(inst.col);
    o.col *= unpack_unorm8(vert.col);
    o.add_col = unpack_signed_color_unorm8(inst.add_col);
    o.tex_slice = inst.tex_slice_vert_offs & 0xff;

    return o;
}