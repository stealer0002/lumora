// March in camera-relative blocks and compare in linear view depth. A ray must
// cross from in front of a surface before that surface can be its reflection.
fn reflection_gap(p: vec3<f32>, depths: texture_depth_2d) -> vec4<f32> {
    let clip = frame.projection * (frame.view * vec4<f32>(p, 1.0));
    if clip.w <= 0.05 { return vec4<f32>(0.0); }
    let ndc = clip.xy / clip.w;
    let uv = ndc * vec2<f32>(0.5, -0.5) + 0.5;
    if any(uv <= vec2<f32>(0.001)) || any(uv >= vec2<f32>(0.999)) {
        return vec4<f32>(0.0);
    }
    let z = textureLoad(depths, vec2<i32>(uv * vec2<f32>(textureDimensions(depths))), 0);
    if z <= 0.0 { return vec4<f32>(uv, -10000.0, 1.0); }
    let scene = frame.projection_inverse * vec4<f32>(ndc, z, 1.0);
    return vec4<f32>(uv, clip.w - 1.0 / max(scene.w, 1e-6), 1.0);
}

fn screen_mirror(p: vec3<f32>, n: vec3<f32>, r: vec3<f32>, depths: texture_depth_2d) -> vec3<f32> {
    let origin = p + n * 0.045;
    let count = 12 + 4 * i32(min(quality, 4u));
    let reach = mix(18.0, 48.0, f32(min(quality, 4u)) * 0.25);
    var front = false;
    var last = 0.0;
    for (var i = 1; i <= count; i++) {
        let t = f32(i) / f32(count);
        let dist = 0.11 + reach * t * t;
        let sample = reflection_gap(origin + r * dist, depths);
        if sample.w == 0.0 { break; }
        if sample.z < 0.0 {
            front = true;
        } else if front {
            var low = last;
            var high = dist;
            var hit = sample;
            for (var j = 0; j < 5; j++) {
                let mid = (low + high) * 0.5;
                let probe = reflection_gap(origin + r * mid, depths);
                if probe.w > 0.0 && probe.z >= 0.0 { high = mid; hit = probe; }
                else { low = mid; }
            }
            // A silhouette may jump from sky to a much nearer depth layer.
            let thickness = min(0.48, 0.10 + high * 0.014);
            if hit.z <= thickness && high > 0.19 {
                let edge = min(hit.xy, 1.0 - hit.xy);
                let trust = smoothstep(0.006, 0.065, min(edge.x, edge.y))
                    * (1.0 - smoothstep(reach * 0.75, reach, high));
                return vec3<f32>(hit.xy, trust);
            }
            front = false;
        }
        last = dist;
    }
    return vec3<f32>(0.0);
}
