// The glow, third step, at a quarter size: the medium halo spread wide (two rings of taps), for
// the soft light round the sun and bright skies.

fn post(input: PostInput) -> vec4<f32> {
    if glow <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let px = 4.0 / frame.resolution;
    var sum = textureSampleLevel(bloom_quarter, linear_sampler, input.uv, 0.0).rgb * 0.16;
    for (var i = 0; i < 8; i++) {
        let a = f32(i) * 0.7853982;
        let o = vec2<f32>(cos(a), sin(a));
        sum += textureSampleLevel(bloom_quarter, linear_sampler, input.uv + o * px * 2.5, 0.0).rgb * 0.065;
        sum += textureSampleLevel(bloom_quarter, linear_sampler, input.uv + vec2<f32>(o.y, -o.x) * px * 6.0, 0.0).rgb * 0.04;
    }
    return vec4<f32>(sum, 1.0);
}
