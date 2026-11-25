// Contact shade (ambient occlusion), at half size: how much of the air round each point of the
// world is taken up by what stands next to it, found from the depth of the picture. Corners,
// the ground under a wall or a tree and the gaps between blocks darken softly; composite.wgsl
// blurs it and lays it over the picture.

fn post(input: PostInput) -> vec4<f32> {
    if !ao_enabled() || frame.eye_in == 2u {
        return vec4<f32>(1.0);
    }
    // The full-size texel under this half-size pixel, read at its centre: the depth and the position
    // rebuilt from it must belong to the same point, or a slanted floor shades itself in stripes.
    let uv = (floor(input.uv * frame.resolution) + 0.5) / frame.resolution;
    let depth = depth_at(uv);
    if depth <= 0.0 {
        return vec4<f32>(1.0);
    }
    let p = view_position(uv, depth);
    let dist = length(p);
    if dist > 96.0 {
        return vec4<f32>(1.0);
    }
    let px = 1.0 / frame.resolution;
    // The surface's normal: the face's own, where the terrain stored it (material.wgsl).
    var n: vec3<f32>;
    let surface = surface_at(vec2<i32>(uv * frame.resolution));
    let exact = surface.present && dot(surface.normal, surface.normal) > 0.5;
    if exact {
        n = normalize(surface.normal);
    } else {
        // Water, glass and mobs leave no surface for the terrain's record: a normal guessed from the
        // depth wobbles on water seen from above and stripes it, so they get no contact shade.
        return vec4<f32>(1.0);
    }
    if dot(n, p) > 0.0 {
        n = -n;
    }
    if ao_accurate() {
        let visibility = ground_visibility(uv, p, n, depth, input.pixel);
        let fade = 1.0 - select(smoothstep(8.0, 20.0, dist), smoothstep(48.0, 96.0, dist), exact);
        return vec4<f32>(vec3<f32>(mix(1.0, visibility, fade)), 1.0);
    }
    // Samples that rise only a little above the surface are its own depth's rounding, not a wall:
    // more so far off, and much more where the normal was only guessed.
    let flat = 0.12 + dist * select(0.006, 0.0015, exact);
    // Look round within about two thirds of a block, in a spiral turned per pixel.
    let radius = 0.7;
    let px_per_block = frame.projection[1][1] * frame.resolution.y * 0.5;
    let reach = clamp(radius * px_per_block / max(dist, 0.1), 3.0, 140.0);
    var counts = array<i32, 4>(6, 8, 12, 16);
    let samples = counts[min(quality, 3u)];
    let dither = fract(52.9829189 * fract(dot(input.pixel, vec2<f32>(0.06711056, 0.00583715))));
    var occlusion = 0.0;
    for (var i = 0; i < samples; i++) {
        let a = (f32(i) + dither) * 2.39996;
        let rr = sqrt((f32(i) + 0.5) / f32(samples)) * reach;
        let suv = (floor((uv + vec2<f32>(cos(a), sin(a)) * rr * px) * frame.resolution) + 0.5) / frame.resolution;
        if any(suv <= vec2<f32>(0.0)) || any(suv >= vec2<f32>(1.0)) {
            continue;
        }
        let sd = depth_at(suv);
        if sd <= 0.0 {
            continue;
        }
        let v = view_position(suv, sd) - p;
        let len = length(v);
        let rise = dot(v / max(len, 0.0001), n);
        occlusion += max(rise - flat, 0.0) * (1.0 - smoothstep(radius * 0.6, radius * 2.2, len));
    }
    let ao = clamp(1.0 - occlusion / f32(samples) * 1.6, 0.0, 1.0);
    // Fades out far away, where a block is a few pixels, and soon where the normal was guessed
    // (water, glass, mobs), whose depth gets too coarse for it a few blocks off.
    let fade = 1.0 - select(smoothstep(8.0, 20.0, dist), smoothstep(48.0, 96.0, dist), exact);
    let v = mix(1.0, ao, fade);
    return vec4<f32>(v, v, v, 1.0);
}
