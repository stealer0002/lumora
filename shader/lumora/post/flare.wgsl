// Five sight lines across the sun's disc, attenuated by the volumetric cloud
// transmittance. Ghosts follow the optical axis as the sun moves off-centre.
fn flare_visibility(uv: vec2<f32>) -> f32 {
    if any(uv <= vec2<f32>(0.0)) || any(uv >= vec2<f32>(1.0)) || depth_at(uv) > 0.0 {
        return 0.0;
    }
    let clouds_here = textureSampleLevel(cloud_kept, linear_sampler, uv, 0.0).a;
    return clamp(clouds_here - 1.0, 0.0, 1.0);
}

fn sun_flare(uv: vec2<f32>) -> vec3<f32> {
    if lens_flare <= 0.0 || !lens_enabled() || !overworld() || frame.eye_in != 0u || frame.sun_direction.y < -0.045 {
        return vec3<f32>(0.0);
    }
    let clip = frame.projection * frame.view * vec4<f32>(frame.sun_direction, 0.0);
    if clip.w <= 0.025 { return vec3<f32>(0.0); }
    let sun = clip.xy / clip.w * vec2<f32>(0.5, -0.5) + 0.5;
    let edge = min(sun, 1.0 - sun);
    let border = smoothstep(0.0, 0.045, min(edge.x, edge.y));
    if border <= 0.0 { return vec3<f32>(0.0); }
    let aspect = vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
    let p = (uv - 0.5) * aspect;
    let axis = (sun - 0.5) * aspect;
    let a = distance(p, -axis * 0.52);
    let b = distance(p, axis * 0.34);
    let c = distance(p, -axis * 0.94);
    let e = distance(p, -axis * 0.25);
    let to_sun = p - axis;
    // Ghosts along the axis through the centre (a warm disc, a green-gold glow, a blue ring, a
    // faint violet disc), and a soft horizontal streak with a halo round the sun itself.
    let shapes = vec3<f32>(0.70, 0.32, 0.14) * (1.0 - smoothstep(0.03, 0.05, a)) * 0.8
        + vec3<f32>(0.16, 0.42, 0.30) * exp(-40.0 * b)
        + vec3<f32>(0.22, 0.34, 0.66) * (1.0 - smoothstep(0.0, 0.016, abs(c - 0.085)))
        + vec3<f32>(0.30, 0.18, 0.45) * (1.0 - smoothstep(0.05, 0.09, e)) * 0.35
        + vec3<f32>(1.0, 0.78, 0.55) * exp(-abs(to_sun.y) * 120.0) * exp(-abs(to_sun.x) * 3.2) * 0.35
        + vec3<f32>(1.0, 0.85, 0.65) * exp(-length(to_sun) * 9.0) * 0.18;
    if max(shapes.r, max(shapes.g, shapes.b)) < 0.002 { return vec3<f32>(0.0); }
    let tap = vec2<f32>(0.005) / aspect;
    let visible = (2.0 * flare_visibility(sun) + flare_visibility(sun + vec2<f32>(tap.x, 0.0))
        + flare_visibility(sun - vec2<f32>(tap.x, 0.0)) + flare_visibility(sun + vec2<f32>(0.0, tap.y))
        + flare_visibility(sun - vec2<f32>(0.0, tap.y))) / 6.0;
    return shapes * (lens_flare * visible * border * day_amount() * (1.0 - wx_overcast()) * 1.6);
}
