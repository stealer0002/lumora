// Smooth edges (FXAA): with a shader pack's post chain the game's own anti-aliasing doesn't run, so
// this pass finds the steps along edges by their brightness and blends across them.

fn edge_luma(c: vec3<f32>) -> f32 {
    // The brightness as the eye will see it after the tone curve, so bright skies don't swamp it.
    let l = luma(c);
    return sqrt(l / (1.0 + l));
}

fn at(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    let centre = at(input.uv);
    if !smooth_edges {
        return vec4<f32>(centre, 1.0);
    }
    let px = 1.0 / vec2<f32>(textureDimensions(previous));
    let nw = edge_luma(at(input.uv + vec2<f32>(-1.0, -1.0) * px));
    let ne = edge_luma(at(input.uv + vec2<f32>(1.0, -1.0) * px));
    let sw = edge_luma(at(input.uv + vec2<f32>(-1.0, 1.0) * px));
    let se = edge_luma(at(input.uv + vec2<f32>(1.0, 1.0) * px));
    let m = edge_luma(centre);
    let lo = min(m, min(min(nw, ne), min(sw, se)));
    let hi = max(m, max(max(nw, ne), max(sw, se)));
    if hi - lo < max(0.04, hi * 0.12) {
        return vec4<f32>(centre, 1.0);
    }
    var dir = vec2<f32>(-((nw + ne) - (sw + se)), (nw + sw) - (ne + se));
    let reduce = max((nw + ne + sw + se) * 0.03125, 1.0 / 128.0);
    let scale = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
    dir = clamp(dir * scale, vec2<f32>(-8.0), vec2<f32>(8.0)) * px;
    let a = 0.5 * (at(input.uv + dir * (1.0 / 3.0 - 0.5)) + at(input.uv + dir * (2.0 / 3.0 - 0.5)));
    let b = a * 0.5 + 0.25 * (at(input.uv - dir * 0.5) + at(input.uv + dir * 0.5));
    let lb = edge_luma(b);
    if lb < lo || lb > hi {
        return vec4<f32>(a, 1.0);
    }
    return vec4<f32>(b, 1.0);
}
