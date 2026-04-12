#include "raven.hlsli"

RV_RESOURCE_SLOT(0, StructuredBuffer<RV_Mesh_Inst_Packed> instances);
RV_RESOURCE_SLOT(1, StructuredBuffer<RV_Vertex_Packed> verts);

RV_Varyings vs_main(uint vid : SV_VertexID, uint inst_id : SV_InstanceID) {
    RV_Mesh_Inst inst = rv_unpack_mesh_inst(instances[inst_id + rv_instance_offset]);
    RV_Vertex vert = rv_unpack_vertex(verts[vid + inst.vert_offs]);

    float3 world_pos = inst.pos + mul(vert.pos, inst.mat);

    RV_Varyings vars;
    vars.pos = mul(rv_view_proj, float4(world_pos, 1.0f));
    vars.world_pos = world_pos;
    vars.normal = mul(vert.normal, adjugate(inst.mat));
    vars.uv = vert.uv;
    vars.col = inst.col * vert.col;
    vars.add_col = inst.add_col;
    vars.tex_slice = inst.tex_slice;

    return vars;
}
