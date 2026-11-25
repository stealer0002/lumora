// Depth of field (option, off by default): what lies far nearer or farther than the point at the
// centre of the screen softens, as through a camera's lens. Gathered over a disc whose size grows
// with how far out of focus each point is.

fn view_distance(uv: vec2<f32>) -> f32 {
    let d = depth_at(uv);
    if d <= 0.0 {
        return frame.far;
    }
    return length(view_position(uv, d));
}

// How wide, in pixels, the blur at distance `dist` is when focused at `focus`: the lens's focus
// (Focus blur), and the far distance softening on its own (Background blur).
fn blur_size(dist: f32, focus: f32) -> f32 {
    let off = abs(dist - focus) / max(dist, 0.5);
    let lens = clamp(off * 14.0 * depth_of_field, 0.0, 14.0 * depth_of_field);
    let far = smoothstep(72.0, 260.0, dist) * 7.0 * background_blur;
    return max(lens, far);
}

fn post(input: PostInput) -> vec4<f32> {
    if (depth_of_field <= 0.0 && background_blur <= 0.0) || !lens_enabled() {
        return input.color;
    }
    // Focus on the middle of the screen (a few points, so a thin edge doesn't snatch it).
    var focus = view_distance(vec2<f32>(0.5, 0.5)) * 0.5;
    focus += view_distance(vec2<f32>(0.48, 0.5)) * 0.125 + view_distance(vec2<f32>(0.52, 0.5)) * 0.125;
    focus += view_distance(vec2<f32>(0.5, 0.47)) * 0.125 + view_distance(vec2<f32>(0.5, 0.53)) * 0.125;
    let here = blur_size(view_distance(input.uv), focus);
    if here < 0.5 {
        return input.color;
    }
    let px = 1.0 / frame.resolution;
    var counts = array<i32, 4>(8, 12, 16, 24);
    let taps = counts[min(quality, 3u)];
    var sum = input.color.rgb;
    var weight = 1.0;
    for (var i = 0; i < taps; i++) {
        let a = f32(i) * 2.39996;
        let rr = sqrt((f32(i) + 0.5) / f32(taps)) * here;
        let suv = clamp(input.uv + vec2<f32>(cos(a), sin(a)) * rr * px, vec2<f32>(0.0), vec2<f32>(1.0));
        // A sharp thing in front doesn't bleed into the blur behind it.
        let theirs = blur_size(view_distance(suv), focus);
        let w = smoothstep(0.0, 1.0, theirs / max(rr, 0.5));
        sum += textureSampleLevel(previous, linear_sampler, suv, 0.0).rgb * w;
        weight += w;
    }
    return vec4<f32>(sum / weight, 1.0);
}
