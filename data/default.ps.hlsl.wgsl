@binding(18) @group(0) var tex_0 : texture_2d_array<f32>;

@binding(0) @group(0) var smp_0 : sampler;

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) world_pos_0 : vec3<f32>,
    @location(1) normal_0 : vec3<f32>,
    @location(2) uv_0 : vec2<f32>,
    @location(3) col_0 : vec4<f32>,
    @location(4) add_col_0 : vec4<f32>,
    @location(5) tex_slice_0 : u32,
};

@fragment
fn ps_main( _S1 : pixelInput_0, @builtin(front_facing) frontface_0 : bool, @builtin(position) pos_0 : vec4<f32>) -> pixelOutput_0
{
    var _S2 : vec3<f32> = vec3<f32>(_S1.uv_0, f32(_S1.tex_slice_0));
    var col_1 : vec4<f32> = _S1.add_col_0 + _S1.col_0 * (textureSample((tex_0), (smp_0), ((_S2)).xy, i32(((_S2)).z)));
    if((col_1.w) < 0.00100000004749745f)
    {
        discard;
    }
    var _S3 : pixelOutput_0 = pixelOutput_0( col_1 );
    return _S3;
}

