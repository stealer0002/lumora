// The glow, second step, at a quarter size: the half-size glow blurred again (a 3x3 tent of
// bilinear taps), for the medium halo.

fn post(input: PostInput) -> vec4<f32> {
    if glow <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let px = 2.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let w = (2.0 - abs(f32(x))) * (2.0 - abs(f32(y))) / 16.0;
            sum += textureSampleLevel(bloom_half, linear_sampler, input.uv + vec2<f32>(f32(x), f32(y)) * px, 0.0).rgb * w;
        }
    }
    return vec4<f32>(sum, 1.0);
}
