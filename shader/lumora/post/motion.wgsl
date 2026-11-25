// A camera shutter in linear scene light. Static geometry is reprojected into the
// previous camera; a point at infinity sees rotation only.
fn post(input: PostInput) -> vec4<f32> {
    let dt = frame.delta_time;
    if !motion_enabled() || dt <= 0.0 || dt > 0.125 || length(frame.camera_motion) > 8.0 {
        return input.color;
    }
    // A camera cut invalidates the shutter over the whole picture.
    let forward = normalize(view_position(vec2<f32>(0.5), 1.0) - eye_offset());
    let last_forward = frame.previous_view_projection * vec4<f32>(forward, 0.0);
    if last_forward.w < 0.55 {
        return input.color;
    }
    let sky = input.depth <= 0.0;
    var previous_clip: vec4<f32>;
    if sky {
        let d = normalize(view_position(input.uv, 1.0) - eye_offset());
        previous_clip = frame.previous_view_projection * vec4<f32>(d, 0.0);
    } else {
        let p = view_position(input.uv, input.depth);
        previous_clip = frame.previous_view_projection * vec4<f32>(p + frame.camera_motion, 1.0);
    }
    if previous_clip.w <= 0.001 {
        return input.color;
    }
    let prev_uv = previous_clip.xy / previous_clip.w * vec2<f32>(0.5, -0.5) + 0.5;
    let size = vec2<f32>(textureDimensions(previous));
    // 0.5 is a 1/120 second exposure. Equal camera speed gives equal streaks at
    // different frame rates. The cap keeps the scene legible during fast turns.
    let travel = (prev_uv - input.uv) * size * (motion_blur / (60.0 * max(dt, 0.001)));
    let span = length(travel);
    if span < 0.7 {
        return input.color;
    }
    let shutter = travel * (min(span, size.y * 0.042) / span) / size;
    let side_taps = min(2 + i32(quality), max(1, i32(ceil(length(shutter * size) / 3.0))));
    let limit = 0.5 / size;
    var sum = input.color.rgb;
    var total = 1.0;
    for (var i = -side_taps; i <= side_taps; i++) {
        if i == 0 { continue; }
        let t = f32(i) / f32(side_taps);
        let uv = input.uv + shutter * (0.5 * t);
        if any(uv < limit) || any(uv > 1.0 - limit) { continue; }
        let z = depth_at(uv);
        if (z <= 0.0) != sky { continue; }
        var w = 1.0 - 0.35 * abs(t);
        if !sky {
            // Reversed depth is proportional to inverse distance. Reject a
            // different depth layer before gathering across a silhouette.
            let dz = abs(z - input.depth) / max(max(z, input.depth), 1e-7);
            w *= 1.0 - smoothstep(0.045, 0.22, dz);
        }
        sum += textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb * w;
        total += w;
    }
    return vec4<f32>(sum / total, input.color.a);
}
