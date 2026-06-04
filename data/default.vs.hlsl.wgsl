struct SLANG_ParameterGroup_rv_batch_constants_std140_0
{
    @align(16) rv_instance_offset_0 : u32,
    @align(4) _pad0_0 : u32,
    @align(8) _pad1_0 : u32,
    @align(4) _pad2_0 : u32,
};

@binding(10) @group(0) var<uniform> rv_batch_constants_0 : SLANG_ParameterGroup_rv_batch_constants_std140_0;
struct RV_Mesh_Inst_Packed_std430_0
{
    @align(16) pos_col_0 : vec4<f32>,
    @align(16) mat_x_add_col_0 : vec4<f32>,
    @align(16) mat_y_tex_slice_vert_offs_0 : vec4<f32>,
    @align(16) mat_z_param_0 : vec4<f32>,
};

@binding(16) @group(0) var<storage, read> instances_0 : array<RV_Mesh_Inst_Packed_std430_0>;

struct RV_Vertex_Packed_std430_0
{
    @align(16) pos_0 : vec4<f32>,
    @align(16) uv_0 : vec2<f32>,
    @align(8) normal_0 : u32,
    @align(4) col_0 : u32,
};

@binding(17) @group(0) var<storage, read> verts_0 : array<RV_Vertex_Packed_std430_0>;

struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct SLANG_ParameterGroup_rv_layer_constants_std140_0
{
    @align(16) rv_view_proj_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) rv_cam_pos_0 : vec3<f32>,
    @align(4) rv_layer_index_0 : i32,
};

@binding(9) @group(0) var<uniform> rv_layer_constants_0 : SLANG_ParameterGroup_rv_layer_constants_std140_0;
fn rv_unpack_unorm8_0( val_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((val_0 & (u32(255)))), f32((((val_0 >> (u32(8)))) & (u32(255)))), f32((((val_0 >> (u32(16)))) & (u32(255)))), f32((((val_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

fn rv_unpack_signed_color_unorm8_0( val_1 : u32) -> vec4<f32>
{
    return rv_unpack_unorm8_0(val_1) * vec4<f32>(4.0f) - vec4<f32>(2.0f);
}

struct RV_Mesh_Inst_0
{
     pos_1 : vec3<f32>,
     col_1 : vec4<f32>,
     mat_0 : mat3x3<f32>,
     add_col_0 : vec4<f32>,
     tex_slice_0 : u32,
     vert_offs_0 : u32,
     param_0 : u32,
};

fn rv_unpack_mesh_inst_0( packed_0 : ptr<function, RV_Mesh_Inst_Packed_std430_0>) -> RV_Mesh_Inst_0
{
    var res_0 : RV_Mesh_Inst_0;
    res_0.pos_1 = (*packed_0).pos_col_0.xyz;
    res_0.col_1 = rv_unpack_signed_color_unorm8_0((bitcast<u32>(((*packed_0).pos_col_0.w))));
    res_0.mat_0 = mat3x3<f32>((*packed_0).mat_x_add_col_0.xyz, (*packed_0).mat_y_tex_slice_vert_offs_0.xyz, (*packed_0).mat_z_param_0.xyz);
    res_0.add_col_0 = rv_unpack_signed_color_unorm8_0((bitcast<u32>(((*packed_0).mat_x_add_col_0.w))));
    var _S1 : u32 = (bitcast<u32>(((*packed_0).mat_y_tex_slice_vert_offs_0.w)));
    res_0.tex_slice_0 = (((_S1 >> (u32(0)))) & (u32(255)));
    res_0.vert_offs_0 = (((_S1 >> (u32(8)))) & (u32(16777215)));
    res_0.param_0 = (bitcast<u32>(((*packed_0).mat_z_param_0.w)));
    return res_0;
}

struct RV_Vertex_0
{
     pos_2 : vec3<f32>,
     uv_1 : vec2<f32>,
     normal_1 : vec3<f32>,
     col_2 : vec4<f32>,
};

fn rv_unpack_vertex_0( packed_1 : ptr<function, RV_Vertex_Packed_std430_0>) -> RV_Vertex_0
{
    var res_1 : RV_Vertex_0;
    res_1.pos_2 = (*packed_1).pos_0.xyz;
    res_1.uv_1 = (*packed_1).uv_0;
    res_1.normal_1 = rv_unpack_unorm8_0((*packed_1).normal_0).xyz * vec3<f32>(2.0f) - vec3<f32>(1.0f);
    res_1.col_2 = rv_unpack_unorm8_0((*packed_1).col_0);
    return res_1;
}

struct RV_Varyings_0
{
    @builtin(position) pos_3 : vec4<f32>,
    @location(0) world_pos_0 : vec3<f32>,
    @location(1) normal_2 : vec3<f32>,
    @location(2) uv_2 : vec2<f32>,
    @location(3) col_3 : vec4<f32>,
    @location(4) add_col_1 : vec4<f32>,
    @interpolate(flat) @location(5) tex_slice_1 : u32,
};

@vertex
fn vs_main(@builtin(vertex_index) vid_0 : u32, @builtin(instance_index) inst_id_0 : u32) -> RV_Varyings_0
{
    var _S2 : RV_Mesh_Inst_Packed_std430_0 = instances_0[inst_id_0 + rv_batch_constants_0.rv_instance_offset_0];
    var _S3 : RV_Mesh_Inst_0 = rv_unpack_mesh_inst_0(&(_S2));
    var _S4 : RV_Vertex_Packed_std430_0 = verts_0[vid_0 + _S3.vert_offs_0];
    var _S5 : RV_Vertex_0 = rv_unpack_vertex_0(&(_S4));
    var world_pos_1 : vec3<f32> = _S3.pos_1 + (((_S3.mat_0) * (_S5.pos_2)));
    var vars_0 : RV_Varyings_0;
    vars_0.pos_3 = (((vec4<f32>(world_pos_1, 1.0f)) * (mat4x4<f32>(rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(3)]))));
    vars_0.world_pos_0 = world_pos_1;
    vars_0.normal_2 = _S5.normal_1;
    vars_0.uv_2 = _S5.uv_1;
    vars_0.col_3 = _S3.col_1 * _S5.col_2;
    vars_0.add_col_1 = _S3.add_col_0;
    vars_0.tex_slice_1 = _S3.tex_slice_0;
    return vars_0;
}

