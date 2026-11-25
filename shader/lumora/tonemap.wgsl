// The tone curve: a soft filmic one, easy on the eyes. Bright light rolls off early and gently
// instead of burning to white, and the brightest colours fade toward their own lightness rather
// than turning loud. Shadows keep a little air in them. A little brighter underground, where the
// eye opens.

fn filmic(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// A gentle curve that reaches white at `white`: straight in the dark, so night and shade keep
// their detail, and slow to brighten toward white.
fn gentle(x: vec3<f32>) -> vec3<f32> {
    let white = 5.0;
    return min(x * (1.0 + x / (white * white)) / (1.0 + x), vec3<f32>(1.0));
}

// The filmic curve's richness, softened by the gentle one: deeper detail in the dark, calmer
// mid-tones, a slow roll to white.
fn blend_curve(x: vec3<f32>) -> vec3<f32> {
    return mix(filmic(x), gentle(x * 1.6), vec3<f32>(0.15) + 0.30 * smoothstep(vec3<f32>(0.08), vec3<f32>(0.8), x));
}

// The curve applied channel by channel (rich, but loud in strong colours) blended with the same
// curve applied to the lightness alone (calm colours, true hues).
fn soft_curve(x: vec3<f32>) -> vec3<f32> {
    let per_channel = blend_curve(x);
    let l = max(luma(x), 0.0001);
    let by_light = x * (blend_curve(vec3<f32>(l)).x / l);
    let k = 0.15 + 0.30 * smoothstep(0.15, 0.9, l);
    return min(mix(per_channel, min(by_light, vec3<f32>(1.0)), k), vec3<f32>(1.0));
}

fn tonemap(input: TonemapInput) -> vec3<f32> {
    let under = 1.0 - frame.eye_light_smooth.y;
    let open_eye = mix(1.0, 1.6, under * (1.0 - 0.5 * frame.eye_light_smooth.x));
    var scene = input.color;
    if chromatic_aberration > 0.0 {
        let dims = vec2<f32>(textureDimensions(previous));
        let radial = (input.uv - 0.5) * 2.0;
        let offset = radial * dot(radial, radial) * (1.25 * chromatic_aberration) / dims;
        scene.r = textureSampleLevel(previous, linear_sampler, input.uv + offset, 0.0).r;
        scene.b = textureSampleLevel(previous, linear_sampler, input.uv - offset, 0.0).b;
    }
    let x = scene * exposure * open_eye * 1.12;
    var y = soft_curve(x);
    // A gentle S on the picture as the eye sees it: shadows a little deeper, light a little
    // brighter, the middle where it was.
    let seen = pow(y, vec3<f32>(1.0 / 2.2));
    let s = seen * seen * (3.0 - 2.0 * seen);
    // Only from the middle up: the dark stays where it was, so nights keep their detail.
    let reach = 0.18 * smoothstep(vec3<f32>(0.2), vec3<f32>(0.5), seen);
    y = pow(mix(seen, s, reach), vec3<f32>(2.2));
    if frame.hdr == 1u {
        // On an HDR display the highlights get some of the room above white, gently.
        let room = min(frame.headroom, 2.0);
        return y + max(soft_curve(x * 0.5) * 2.0 - y, vec3<f32>(0.0)) * (room - 1.0) * 0.4;
    }
    return y;
}
