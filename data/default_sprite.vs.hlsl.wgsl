struct SLANG_ParameterGroup_rv_batch_constants_std140_0
{
    @align(16) rv_instance_offset_0 : u32,
    @align(4) _pad0_0 : u32,
    @align(8) _pad1_0 : u32,
    @align(4) _pad2_0 : u32,
};

@binding(10) @group(0) var<uniform> rv_batch_constants_0 : SLANG_ParameterGroup_rv_batch_constants_std140_0;
struct RV_Sprite_Inst_Packed_std430_0
{
    @align(16) pos_col_0 : vec4<f32>,
    @align(16) mat_x_uv_min_0 : vec4<f32>,
    @align(16) mat_y_uv_size_0 : vec4<f32>,
    @align(16) add_col_0 : u32,
    @align(4) param_0 : u32,
    @align(8) tex_slice_0 : u32,
    @align(4) _pad0_1 : u32,
};

@binding(16) @group(0) var<storage, read> instances_0 : array<RV_Sprite_Inst_Packed_std430_0>;

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

fn rv_unpack_unorm16_0( val_2 : u32) -> vec2<f32>
{
    return vec2<f32>(f32((val_2 & (u32(65535)))), f32((((val_2 >> (u32(16)))) & (u32(65535))))) * vec2<f32>(0.00001525902189314f);
}

fn rv_unpack_uv_unorm16_0( val_3 : u32) -> vec2<f32>
{
    return rv_unpack_unorm16_0(val_3) * vec2<f32>(32.0f) - vec2<f32>(16.0f);
}

struct RV_Sprite_Inst_0
{
     pos_0 : vec3<f32>,
     col_0 : vec4<f32>,
     mat_x_0 : vec3<f32>,
     mat_y_0 : vec3<f32>,
     uv_min_0 : vec2<f32>,
     uv_size_0 : vec2<f32>,
     add_col_1 : vec4<f32>,
     param_1 : u32,
     tex_slice_1 : u32,
};

fn rv_unpack_sprite_inst_0( packed_0 : ptr<function, RV_Sprite_Inst_Packed_std430_0>) -> RV_Sprite_Inst_0
{
    var res_0 : RV_Sprite_Inst_0;
    res_0.pos_0 = (*packed_0).pos_col_0.xyz;
    res_0.col_0 = rv_unpack_signed_color_unorm8_0((bitcast<u32>(((*packed_0).pos_col_0.w))));
    res_0.mat_x_0 = (*packed_0).mat_x_uv_min_0.xyz;
    res_0.mat_y_0 = (*packed_0).mat_y_uv_size_0.xyz;
    res_0.uv_min_0 = rv_unpack_uv_unorm16_0((bitcast<u32>(((*packed_0).mat_x_uv_min_0.w))));
    res_0.uv_size_0 = rv_unpack_uv_unorm16_0((bitcast<u32>(((*packed_0).mat_y_uv_size_0.w))));
    res_0.add_col_1 = rv_unpack_signed_color_unorm8_0((*packed_0).add_col_0);
    res_0.param_1 = (*packed_0).param_0;
    res_0.tex_slice_1 = (*packed_0).tex_slice_0;
    return res_0;
}

struct RV_Varyings_0
{
    @builtin(position) pos_1 : vec4<f32>,
    @location(0) world_pos_0 : vec3<f32>,
    @location(1) normal_0 : vec3<f32>,
    @location(2) uv_0 : vec2<f32>,
    @location(3) col_1 : vec4<f32>,
    @location(4) add_col_2 : vec4<f32>,
    @interpolate(flat) @location(5) tex_slice_2 : u32,
};

@vertex
fn vs_main(@builtin(vertex_index) vid_0 : u32, @builtin(instance_index) inst_id_0 : u32) -> RV_Varyings_0
{
    var _S1 : RV_Sprite_Inst_Packed_std430_0 = instances_0[inst_id_0 + rv_batch_constants_0.rv_instance_offset_0];
    var _S2 : RV_Sprite_Inst_0 = rv_unpack_sprite_inst_0(&(_S1));
    var local_uv_0 : vec2<f32> = vec2<f32>(f32((vid_0 & (u32(1)))), f32(vid_0 / u32(2)));
    var local_pos_0 : vec2<f32> = local_uv_0 * vec2<f32>(2.0f) - vec2<f32>(1.0f);
    var world_pos_1 : vec3<f32> = _S2.pos_0 + _S2.mat_x_0 * vec3<f32>(local_pos_0.x) + _S2.mat_y_0 * vec3<f32>(local_pos_0.y);
    var vars_0 : RV_Varyings_0;
    vars_0.pos_1 = (((vec4<f32>(world_pos_1, 1.0f)) * (mat4x4<f32>(rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(0)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(1)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(2)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(0)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(1)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(2)][i32(3)], rv_layer_constants_0.rv_view_proj_0.data_0[i32(3)][i32(3)]))));
    vars_0.world_pos_0 = world_pos_1;
    vars_0.normal_0 = cross(_S2.mat_x_0, _S2.mat_y_0);
    vars_0.uv_0 = _S2.uv_min_0 + _S2.uv_size_0 * local_uv_0;
    vars_0.col_1 = _S2.col_0;
    vars_0.add_col_2 = _S2.add_col_1;
    vars_0.tex_slice_2 = _S2.tex_slice_1;
    return vars_0;
}

