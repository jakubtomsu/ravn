struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct SLANG_ParameterGroup_constants_std140_0
{
    @align(16) proj_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
};

@binding(0) @group(0) var<uniform> constants_0 : SLANG_ParameterGroup_constants_std140_0;
struct VS_Out_0
{
    @builtin(position) pos_0 : vec4<f32>,
    @location(0) col_0 : vec4<f32>,
};

struct vertexInput_0
{
    @location(0) pos_1 : vec3<f32>,
    @location(1) col_1 : vec4<f32>,
};

@vertex
fn vs_main( _S1 : vertexInput_0) -> VS_Out_0
{
    var o_0 : VS_Out_0;
    o_0.pos_0 = (((vec4<f32>(_S1.pos_1.xyz, 1.0f)) * (mat4x4<f32>(constants_0.proj_0.data_0[i32(0)][i32(0)], constants_0.proj_0.data_0[i32(1)][i32(0)], constants_0.proj_0.data_0[i32(2)][i32(0)], constants_0.proj_0.data_0[i32(3)][i32(0)], constants_0.proj_0.data_0[i32(0)][i32(1)], constants_0.proj_0.data_0[i32(1)][i32(1)], constants_0.proj_0.data_0[i32(2)][i32(1)], constants_0.proj_0.data_0[i32(3)][i32(1)], constants_0.proj_0.data_0[i32(0)][i32(2)], constants_0.proj_0.data_0[i32(1)][i32(2)], constants_0.proj_0.data_0[i32(2)][i32(2)], constants_0.proj_0.data_0[i32(3)][i32(2)], constants_0.proj_0.data_0[i32(0)][i32(3)], constants_0.proj_0.data_0[i32(1)][i32(3)], constants_0.proj_0.data_0[i32(2)][i32(3)], constants_0.proj_0.data_0[i32(3)][i32(3)]))));
    o_0.col_0 = _S1.col_1;
    return o_0;
}

