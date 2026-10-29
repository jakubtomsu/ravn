@binding(1) @group(0) var texture0_0 : texture_2d<f32>;

@binding(2) @group(0) var sampler0_0 : sampler;

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) col_0 : vec4<f32>,
    @location(1) uv_0 : vec2<f32>,
};

@fragment
fn ps_main( _S1 : pixelInput_0, @builtin(position) pos_0 : vec4<f32>) -> pixelOutput_0
{
    var _S2 : pixelOutput_0 = pixelOutput_0( _S1.col_0 * (textureSample((texture0_0), (sampler0_0), (_S1.uv_0))) );
    return _S2;
}

