// The glow, first step, at half size: the light of what is brighter than about white (the sun,
// lava, torches, fireflies, a bright sky), with a soft knee, gathered over a 4x4 area.

fn bright(c: vec3<f32>) -> vec3<f32> {
    let l = luma(c);
    let knee = clamp((l - 1.3) / 1.5, 0.0, 1.0);
    return c * knee * knee;
}

fn post(input: PostInput) -> vec4<f32> {
    if glow <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let px = 1.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    // Thirteen taps (the "dual box" downsample): a centre box and four corner boxes.
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv, 0.0).rgb) * 0.125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(-1.0, -1.0), 0.0).rgb) * 0.125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(1.0, -1.0), 0.0).rgb) * 0.125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(-1.0, 1.0), 0.0).rgb) * 0.125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(1.0, 1.0), 0.0).rgb) * 0.125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(-2.0, -2.0), 0.0).rgb) * 0.03125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(0.0, -2.0), 0.0).rgb) * 0.0625;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(2.0, -2.0), 0.0).rgb) * 0.03125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(-2.0, 0.0), 0.0).rgb) * 0.0625;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(2.0, 0.0), 0.0).rgb) * 0.0625;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(-2.0, 2.0), 0.0).rgb) * 0.03125;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(0.0, 2.0), 0.0).rgb) * 0.0625;
    sum += bright(textureSampleLevel(previous, linear_sampler, input.uv + px * vec2<f32>(2.0, 2.0), 0.0).rgb) * 0.03125;
    return vec4<f32>(sum, 1.0);
}
