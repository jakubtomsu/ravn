struct SLANG_ParameterGroup_batch_constants_std140_0
{
    @align(16) instance_offset_0 : u32,
    @align(4) vertex_offset_0 : u32,
};

@binding(10) @group(0) var<uniform> batch_constants_0 : SLANG_ParameterGroup_batch_constants_std140_0;
struct Sprite_Inst_std430_0
{
    @align(16) pos_0 : vec3<f32>,
    @align(4) col_0 : u32,
    @align(16) mat_x_0 : vec3<f32>,
    @align(4) uv_min_0 : u32,
    @align(16) mat_y_0 : vec3<f32>,
    @align(4) uv_size_0 : u32,
    @align(16) add_col_0 : u32,
    @align(4) param_0 : u32,
    @align(8) tex_slice_0 : u32,
    @align(4) _pad0_0 : u32,
};

@binding(16) @group(0) var<storage, read> instances_0 : array<Sprite_Inst_std430_0>;

struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct SLANG_ParameterGroup_layer_constants_std140_0
{
    @align(16) view_proj_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) cam_pos_0 : vec3<f32>,
    @align(4) layer_index_0 : i32,
};

@binding(9) @group(0) var<uniform> layer_constants_0 : SLANG_ParameterGroup_layer_constants_std140_0;
fn unpack_unorm16_0( val_0 : u32) -> vec2<f32>
{
    return vec2<f32>(f32((val_0 & (u32(65535)))), f32((((val_0 >> (u32(16)))) & (u32(65535))))) * vec2<f32>(0.00001525902189314f);
}

fn unpack_uv_unorm16_0( val_1 : u32) -> vec2<f32>
{
    return unpack_unorm16_0(val_1) * vec2<f32>(16.0f) - vec2<f32>(8.0f);
}

fn unpack_unorm8_0( val_2 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((val_2 & (u32(255)))), f32((((val_2 >> (u32(8)))) & (u32(255)))), f32((((val_2 >> (u32(16)))) & (u32(255)))), f32((((val_2 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

fn unpack_signed_color_unorm8_0( val_3 : u32) -> vec4<f32>
{
    return unpack_unorm8_0(val_3) * vec4<f32>(4.0f) - vec4<f32>(2.0f);
}

struct VS_Out_0
{
    @builtin(position) pos_1 : vec4<f32>,
    @location(0) world_pos_0 : vec3<f32>,
    @location(1) normal_0 : vec3<f32>,
    @location(2) uv_0 : vec2<f32>,
    @location(3) col_1 : vec4<f32>,
    @location(4) add_col_1 : vec4<f32>,
    @location(5) tex_slice_1 : u32,
};

@vertex
fn vs_main(@builtin(vertex_index) vid_0 : u32, @builtin(instance_index) inst_id_0 : u32) -> VS_Out_0
{
    var inst_0 : Sprite_Inst_std430_0 = instances_0[inst_id_0 + batch_constants_0.instance_offset_0];
    var local_uv_0 : vec2<f32> = vec2<f32>(f32((vid_0 & (u32(1)))), f32(vid_0 / u32(2)));
    var local_pos_0 : vec2<f32> = local_uv_0 * vec2<f32>(2.0f) - vec2<f32>(1.0f);
    var uv_min_1 : vec2<f32> = unpack_uv_unorm16_0(inst_0.uv_min_0);
    var uv_size_1 : vec2<f32> = unpack_uv_unorm16_0(inst_0.uv_size_0);
    var world_pos_1 : vec3<f32> = inst_0.pos_0 + inst_0.mat_x_0 * vec3<f32>(local_pos_0.x) + inst_0.mat_y_0 * vec3<f32>(local_pos_0.y);
    var o_0 : VS_Out_0;
    o_0.pos_1 = (((vec4<f32>(world_pos_1, 1.0f)) * (mat4x4<f32>(layer_constants_0.view_proj_0.data_0[i32(0)][i32(0)], layer_constants_0.view_proj_0.data_0[i32(1)][i32(0)], layer_constants_0.view_proj_0.data_0[i32(2)][i32(0)], layer_constants_0.view_proj_0.data_0[i32(3)][i32(0)], layer_constants_0.view_proj_0.data_0[i32(0)][i32(1)], layer_constants_0.view_proj_0.data_0[i32(1)][i32(1)], layer_constants_0.view_proj_0.data_0[i32(2)][i32(1)], layer_constants_0.view_proj_0.data_0[i32(3)][i32(1)], layer_constants_0.view_proj_0.data_0[i32(0)][i32(2)], layer_constants_0.view_proj_0.data_0[i32(1)][i32(2)], layer_constants_0.view_proj_0.data_0[i32(2)][i32(2)], layer_constants_0.view_proj_0.data_0[i32(3)][i32(2)], layer_constants_0.view_proj_0.data_0[i32(0)][i32(3)], layer_constants_0.view_proj_0.data_0[i32(1)][i32(3)], layer_constants_0.view_proj_0.data_0[i32(2)][i32(3)], layer_constants_0.view_proj_0.data_0[i32(3)][i32(3)]))));
    o_0.world_pos_0 = world_pos_1;
    o_0.normal_0 = cross(inst_0.mat_x_0, inst_0.mat_y_0);
    o_0.uv_0 = uv_min_1 + uv_size_1 * local_uv_0;
    o_0.col_1 = unpack_signed_color_unorm8_0(inst_0.col_0);
    o_0.add_col_1 = unpack_signed_color_unorm8_0(inst_0.add_col_0);
    o_0.tex_slice_1 = inst_0.tex_slice_0;
    return o_0;
}

