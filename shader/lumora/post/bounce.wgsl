// A first bounce of light, at half size (Max quality only): every lit surface near a point sends
// a little of its colour on to it, so a sunlit wooden floor warms the stone walls round it and a
// green lawn tints the underside of an overhang. Gathered from the picture itself: a few points
// round each pixel, within a few blocks in the world, each counted only when it faces the point and
// the point faces it (so light doesn't leak through a wall from its far side), weighted by the two
// angles and the distance. composite.wgsl blurs it, scales it by the surface's own colour and by how
// enclosed it is, and adds it: outdoors the sky's light already plays this part.

fn post(input: PostInput) -> vec4<f32> {
    let path_mode = ray_mode == 2u && ray_ready();
    if (!max_quality() && !path_mode) || bounce_light <= 0.0 || input.depth <= 0.0 || frame.eye_in != 0u {
        return vec4<f32>(0.0);
    }
    let size = frame.resolution;
    let here_texel = vec2<i32>(input.uv * size);
    let here = surface_at(here_texel);
    if !here.present {
        return vec4<f32>(0.0);
    }
    let n = normalize(here.normal);
    let p = view_position(input.uv, input.depth);
    let dist = length(p);
    if dist > 48.0 {
        return vec4<f32>(0.0);
    }
    if path_mode { return path_gather(input, p, n); }
    // Look about six blocks round (a room's width), in a spiral turned per pixel. Each point stands
    // for its share of that disc of surface.
    let px_per_block = frame.projection[1][1] * size.y * 0.5;
    let world_reach = 6.0;
    let reach = clamp(world_reach * px_per_block / max(dist, 0.5), 6.0, 640.0);
    // The share of the disc on screen each point stands for, in pixels; turned into blocks of
    // surface at that point's own distance and slant below.
    let px_share = 3.14159265 * reach * reach / f32(12);
    let turn = fract(52.9829189 * fract(dot(input.pixel, vec2<f32>(0.06711056, 0.00583715)))) * 6.2831853;
    let taps = 12;
    var gathered = vec3<f32>(0.0);
    for (var i = 0; i < taps; i++) {
        let a = f32(i) * 2.3999632 + turn;
        let r = sqrt((f32(i) + 0.5) / f32(taps)) * reach;
        let suv = input.uv + vec2<f32>(cos(a), sin(a)) * r / size;
        if any(suv <= vec2<f32>(0.0)) || any(suv >= vec2<f32>(1.0)) {
            continue;
        }
        let sd = depth_at(suv);
        if sd <= 0.0 {
            continue;
        }
        let v = view_position(suv, sd) - p;
        let len = length(v);
        // Too close (a neighbouring face of the same block) would only light itself.
        if len < 0.35 || len > 8.0 {
            continue;
        }
        let dir = v / len;
        let cos_here = dot(n, dir);
        if cos_here <= 0.05 {
            continue;
        }
        let there = surface_at(vec2<i32>(suv * size));
        var cos_there = 1.0;
        var n_there = -dir;
        if there.present {
            n_there = normalize(there.normal);
            cos_there = dot(n_there, -dir);
        }
        if cos_there <= 0.05 {
            continue;
        }
        // The surface that point stands for: its pixel share at its distance, larger the more
        // the surface is seen edge-on.
        let at = view_position(suv, sd);
        let at_dist = length(at);
        let facing_eye = max(abs(dot(n_there, at / max(at_dist, 0.001))), 0.25);
        let area = px_share * (at_dist / px_per_block) * (at_dist / px_per_block) / facing_eye;
        // What that point sends out: its lit colour, kept from blowing up on the sun's own glare.
        let sent = min(textureSampleLevel(previous, linear_sampler, suv, 0.0).rgb, vec3<f32>(1.5));
        gathered += min(sent * cos_here * cos_there * area / (len * len + 0.6), vec3<f32>(3.0));
    }
    // Lambert's 1/pi for the light each surface sends on.
    let bounce = gathered * 0.3183;
    return vec4<f32>(bounce, 0.0);
}
