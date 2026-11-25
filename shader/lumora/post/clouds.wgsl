// The clouds, at half size, in one pass: ray marched through both cloud layers (clouds_march.wgsl)
// for every pixel the sky shows through, keeping the light they send toward the eye (rgb) and how
// much of what lies behind still shows (alpha) together in a kept texture, cloud_kept, whose alpha
// is kept as it is. Encoded alpha: 1 + transmittance where there are clouds, 1 where nothing is
// drawn (the sky clear behind), and 0 for "nothing yet" (a cleared texture), which the history
// below treats as missing.
//
// With the option temporal_clouds, each frame marches half the steps with a new offset and adds
// to what the last frames found there, looked up where that piece of sky was last frame (the
// clouds are far: the view's turn is all that moves them on screen). The history is dropped where
// it is missing, off screen, behind land last frame, after a pause, and in a lightning flash.

fn clouds_now(uv: vec2<f32>, pixel: vec2<f32>) -> vec4<f32> {
    let d = normalize(view_position(uv, 1.0) - eye_offset());
    var jitter = fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
    if !temporal_clouds {
        return clouds_all(d, jitter, true);
    }
    jitter = fract(jitter + f32(frame.frame_index % 64u) * 0.618034);
    cloud_step_scale = 0.5;
    let now = clouds_all(d, jitter, true);
    // Where was this piece of sky last frame?
    let clip = frame.previous_view_projection * vec4<f32>(d, 0.0);
    if clip.w <= 0.0001 || frame.delta_time <= 0.0 || lightning_flash() > 0.001 {
        return now;
    }
    let ndc = clip.xy / clip.w;
    let then_uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if any(then_uv < vec2<f32>(0.0)) || any(then_uv > vec2<f32>(1.0)) {
        return now;
    }
    // The nearest texel, not a blend: a blend with land would read as cloud.
    let size = vec2<f32>(textureDimensions(cloud_kept_previous));
    let then = textureLoad(cloud_kept_previous, vec2<i32>(clamp(then_uv * size, vec2<f32>(0.0), size - 1.0)), 0);
    // Missing or mixed with land last frame: start again.
    if then.a < 0.999 {
        return now;
    }
    let history = vec4<f32>(then.rgb, then.a - 1.0);
    return mix(history, now, 0.3);
}

fn post(input: PostInput) -> vec4<f32> {
    load_weather();
    if !overworld() || cloud_cover() <= 0.01 || frame.eye_in != 0u {
        return vec4<f32>(0.0, 0.0, 0.0, 2.0);
    }
    // Where the world covers all four of the picture's pixels under this one, no cloud shows.
    let px = 1.0 / frame.resolution;
    let covered = depth_at(input.uv + vec2<f32>(-px.x, -px.y)) > 0.0 && depth_at(input.uv + vec2<f32>(px.x, -px.y)) > 0.0
        && depth_at(input.uv + vec2<f32>(-px.x, px.y)) > 0.0 && depth_at(input.uv + vec2<f32>(px.x, px.y)) > 0.0;
    if covered {
        // Land: no clouds, and no history to keep here.
        return vec4<f32>(0.0, 0.0, 0.0, 0.5);
    }
    let c = clouds_now(input.uv, input.pixel);
    return vec4<f32>(c.rgb, 1.0 + clamp(c.a, 0.0, 1.0));
}
