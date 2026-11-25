// Light shafts, at half size: the sunlight (the moonlight by night) the air between the camera and
// each pixel scatters toward the eye. The ray is walked through the shadow map, so where trees,
// hills and walls block the light the air stays dark: beams through the leaves, rays round a
// low sun, a glow in the morning haze.

fn henyey_greenstein(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.0001), 1.5));
}

// How much of the air at camera-relative `p` the light reaches: 1 lit, 0 shaded.
fn air_lit(p: vec3<f32>) -> f32 {
    let s = shadow_position(p);
    if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) || s.z >= 1.0 {
        return 1.0;
    }
    return textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z);
}

fn post(input: PostInput) -> vec4<f32> {
    load_weather();
    if !overworld() || frame.has_shadow == 0u || !shafts_enabled() || frame.eye_in != 0u {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let depth = depth_at(input.uv);
    let dir = normalize(view_position(input.uv, 1.0) - eye_offset());
    let reach = frame.shadow_distance * 0.95;
    var dist = reach;
    if depth > 0.0 {
        dist = min(length(view_position(input.uv, depth) - eye_offset()), reach);
    }
    // A dither so a few steps look like many; the composite pass blurs it away.
    let dither = fract(52.9829189 * fract(dot(input.pixel, vec2<f32>(0.06711056, 0.00583715))));
    var counts = array<i32, 4>(8, 12, 18, 28);
    let steps = counts[min(quality, 3u)];
    var lit = 0.0;
    for (var i = 0; i < steps; i++) {
        // Steps closer together near the camera, where shafts are seen best.
        let f = (f32(i) + dither) / f32(steps);
        lit += air_lit(eye_offset() + dir * (f * f * dist));
    }
    lit /= f32(steps);
    // The air is thicker at dawn and dusk, in rain and in the night's mist.
    let sigma = (0.004 + 0.006 * twilight_amount() + 0.006 * wx_overcast() + 0.004 * night_amount()) * fog_density;
    let amount = 1.0 - exp(-dist * sigma);
    let cos_theta = dot(dir, frame.light_direction);
    let phase = henyey_greenstein(cos_theta, 0.76) * 2.0 + 0.03;
    let outdoors = smoothstep(0.3, 0.9, frame.eye_light_smooth.y);
    let colour = direct_light() * lit * amount * phase * outdoors * god_rays * 0.18;
    return vec4<f32>(colour, 1.0);
}
