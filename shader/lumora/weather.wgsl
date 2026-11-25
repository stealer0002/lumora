// Rain and snow: grey-white streaks lit by the sky's light (and torches nearby), fainter than the
// game's blue ones, so the storm reads as a curtain of water rather than blue lines.

fn weather(input: WeatherInput) -> vec4<f32> {
    let grey = luma(input.color.rgb);
    var tone = select(vec3<f32>(0.78, 0.84, 0.92), vec3<f32>(1.0), input.snow);
    let sky = sky_ambient() * input.light.y * 1.3;
    let torch = rgb(1.0, 0.74, 0.48) * pow(input.light.x, 2.4) * 1.2;
    let light = sky + torch + vec3<f32>(0.01);
    let colour = tone * grey * light;
    let alpha = input.color.a * select(0.3, 0.8, input.snow);
    return vec4<f32>(apply_fog(colour, input.position), alpha);
}
