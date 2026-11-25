// The clouds laid over the sky, then fireflies: on warm nights outdoors, small yellow-green lights drift in the air round the player
// and blink. Each lives in a cell of the world (so it stays where it is as you walk), hides behind
// what stands in front of it, and fades in and out as the night does.

const FIREFLY_CELL: f32 = 6.0;
const FIREFLY_LAYER: f32 = 4.0;

// How many come out here and now, 0..1: at night, outdoors, in neither the cold nor the desert, and
// not in rain.
fn firefly_night() -> f32 {
    if !overworld() || frame.eye_in != 0u {
        return 0.0;
    }
    let warm = smoothstep(0.2, 0.45, biome_temperature()) * (1.0 - smoothstep(1.3, 1.7, biome_temperature()));
    let damp = smoothstep(0.02, 0.25, biome_downfall());
    let dry = 1.0 - smoothstep(0.05, 0.35, wx_overcast());
    let outdoors = smoothstep(0.45, 0.9, frame.eye_light_smooth.y);
    return night_amount() * warm * damp * dry * outdoors;
}

// The End's sky (the stage `sky` draws only the Overworld): deep violet, a slow nebula and
// still, cold stars.
// The End's sky has one subject: the Rift, a tall narrow tear in the violet dark, fixed low in
// one part of the sky. Its edges burn pale teal, fading to violet; it slowly breathes; threads of
// light drift into it and the nebula leans toward it. The stars are few, and the bright ones
// gather near it.
const RIFT_CENTER: vec3<f32> = vec3<f32>(0.75, 0.34, -0.57);

fn end_sky(d: vec3<f32>) -> vec3<f32> {
    let rc = normalize(RIFT_CENTER);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), rc));
    let upv = cross(rc, right);
    let facing = dot(d, rc);
    let x = dot(d, right);
    let y = dot(d, upv);
    let t = frame.time;

    let up = d.y * 0.5 + 0.5;
    var c = mix(rgb(0.04, 0.018, 0.06), rgb(0.10, 0.05, 0.15), up);

    // The nebula, bent toward the Rift and fading on the far side of the sky.
    let toward = clamp(facing, 0.0, 1.0);
    let bent = normalize(d + (rc - d) * 0.3 * toward);
    let neb = fbm3(bent * 2.2 + vec3<f32>(t * 0.004, 0.0, 0.0));
    let wisps = smoothstep(0.45, 0.8, neb) * smoothstep(0.3, 0.7, fbm3(bent * 5.0 + 3.0));
    let near_side = smoothstep(-0.4, 0.6, facing);
    c += mix(rgb(0.45, 0.2, 0.6), rgb(0.2, 0.45, 0.6), fbm3(d * 3.0 + 9.0)) * wisps * 0.12 * near_side;

    if facing > 0.0 {
        // The tear: a lens about 3 degrees wide and 25 tall, its width breathing over 40 seconds.
        let height = 0.3;
        let breath = 1.0 + 0.15 * sin(t * 6.2831853 / 40.0);
        let along = clamp(1.0 - (y / height) * (y / height), 0.0, 1.0);
        // A ragged edge, not a drawn outline.
        let ragged = 1.0 + 0.45 * (fbm3(vec3<f32>(y * 16.0, t * 0.05, 1.0)) - 0.5);
        let half_width = 0.034 * breath * along * ragged;
        let ax = abs(x);
        let outside = ax - half_width;
        let in_lens = select(0.0, 1.0, outside < 0.0 && along > 0.0);
        // Emptier than the sky inside.
        c *= mix(1.0, 0.5, in_lens);
        // A thin burning edge, pale teal-white, and violet light spilling out from it.
        let rim = exp(-pow(outside / 0.003, 2.0)) * smoothstep(0.0, 0.25, along) * (0.6 + 0.4 * fbm3(vec3<f32>(y * 40.0, t * 0.3, 5.0)));
        let spill = exp(-max(outside, 0.0) / 0.06) * pow(along, 0.6) * (1.0 - in_lens);
        c += rgb(0.7, 0.95, 1.0) * rim * 0.9 + rgb(0.42, 0.24, 0.7) * spill * 0.3;
        // Threads of light drifting in toward the tear along both edges.
        let flow = fbm3(vec3<f32>(ax * 26.0 + t * 0.52, y * 9.0, t * 0.03));
        let threads = smoothstep(0.52, 0.72, flow) * exp(-ax / 0.1) * smoothstep(0.0, 0.3, along + 0.2) * exp(-max(abs(y) - height, 0.0) / 0.08) * (1.0 - in_lens);
        c += mix(rgb(0.5, 0.3, 0.8), rgb(0.6, 0.9, 1.0), exp(-ax / 0.03)) * threads * 0.28;
    }

    // Stars: few, and only those near the Rift may be bright.
    let q = d * 160.0;
    let cell = floor(q);
    let h = hash33(cell + 2.0);
    if h.x < 0.012 {
        let star = normalize(cell + 0.25 + 0.5 * hash33(cell + 7.7));
        let off = length(d - star);
        let radius = max(2.0 / (frame.projection[1][1] * frame.resolution.y), 0.0005);
        let near_rift = smoothstep(0.55, 0.85, facing);
        c += mix(rgb(0.8, 0.75, 1.0), rgb(1.0, 0.9, 0.85), h.z) * exp(-off * off / (radius * radius)) * (0.12 + pow(h.y, 5.0) * 3.0 * near_rift);
    }
    return c;
}

fn post(input: PostInput) -> vec4<f32> {
    load_weather();
    var colour = input.color.rgb;
    if other_skies && frame.dimension == 1 && input.depth <= 0.0 && frame.eye_in == 0u {
        let d = normalize(view_position(input.uv, 1.0) - eye_offset());
        return vec4<f32>(end_sky(d), 1.0);
    }
    // The Nether: the hot air shimmers over the distance and glows a little redder.
    if other_skies && frame.dimension == -1 && frame.eye_in != 1u {
        var dist = frame.far;
        if input.depth > 0.0 {
            dist = length(view_position(input.uv, input.depth));
        }
        let amount = smoothstep(6.0, 48.0, dist);
        let t = frame.time;
        let w = vec2<f32>(
            noise2(input.uv * vec2<f32>(9.0, 5.0) + vec2<f32>(0.0, t * 1.3)) - 0.5,
            noise2(input.uv * vec2<f32>(7.0, 4.0) + vec2<f32>(3.1, t * 1.7)) - 0.5,
        );
        let uv = clamp(input.uv + w * 0.004 * amount, vec2<f32>(0.0), vec2<f32>(1.0));
        let hot = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
        colour = mix(hot, hot * rgb(1.12, 0.92, 0.85), amount * 0.6);
        return vec4<f32>(colour, 1.0);
    }
    // The clouds (post/clouds.wgsl) over the sky.
    if input.depth <= 0.0 && overworld() {
        // cloud_kept: rgb their light, alpha 1 + how much of the sky shows through (post/clouds.wgsl).
        let c = textureSampleLevel(cloud_kept, linear_sampler, input.uv, 0.0);
        let through = select(1.0, clamp(c.a - 1.0, 0.0, 1.0), c.a >= 1.0);
        colour = colour * through + c.rgb * select(0.0, 1.0, c.a >= 1.0);
    }
    // A rainbow, in the rain in front of the clouds and of far land.
    let bow = rainbow_amount();
    if bow > 0.001 && frame.eye_in == 0u {
        var far_enough = 1.0;
        if input.depth > 0.0 {
            far_enough = smoothstep(64.0, 160.0, length(view_position(input.uv, input.depth)));
        }
        if far_enough > 0.0 {
            let d = normalize(view_position(input.uv, 1.0) - eye_offset());
            colour += rainbow_light(d) * bow * far_enough * luma(sky_ambient()) * 0.3;
        }
    }
    let amount = firefly_night();
    if amount <= 0.001 || fireflies <= 0.0 {
        return vec4<f32>(colour, 1.0);
    }
    let cam = frame.camera_position;
    let base = floor(cam.xz / FIREFLY_CELL);
    let floor_y = floor((cam.y - 2.0) / FIREFLY_LAYER);
    let to_clip = frame.projection * frame.view;
    let px_per_block = frame.projection[1][1] * frame.resolution.y * 0.5;
    let t = frame.time;
    let chance = 0.45 * fireflies;
    let tone = rgb(0.86, 1.0, 0.38);
    var add = vec3<f32>(0.0);
    for (var layer = 0; layer < 2; layer++) {
        for (var dz = -2; dz <= 2; dz++) {
            for (var dx = -2; dx <= 2; dx++) {
                let cell = vec3<f32>(base.x + f32(dx), floor_y + f32(layer), base.y + f32(dz));
                let h = hash33(cell * vec3<f32>(1.0, 3.0, 1.0) + 11.0);
                if h.x > chance {
                    continue;
                }
                let h2 = hash33(cell + 41.7);
                let home = vec3<f32>(
                    (cell.x + 0.1 + 0.8 * h.y) * FIREFLY_CELL,
                    (cell.y + 0.1 + 0.8 * h2.x) * FIREFLY_LAYER,
                    (cell.z + 0.1 + 0.8 * h.z) * FIREFLY_CELL,
                );
                // A slow wander, with a little flutter on top.
                let drift = vec3<f32>(
                    sin(t * 0.33 + h2.y * 25.0) * 1.3 + sin(t * 1.7 + h.z * 9.0) * 0.12,
                    sin(t * 0.51 + h2.z * 19.0) * 0.6,
                    cos(t * 0.29 + h.y * 31.0) * 1.3 + cos(t * 1.4 + h2.x * 7.0) * 0.12,
                );
                let at = home + drift;
                // Only within a few blocks of the player's height: they fade as you climb or drop.
                let near_height = 1.0 - smoothstep(3.0, 5.5, abs(at.y - (cam.y + 0.5)));
                if near_height <= 0.0 {
                    continue;
                }
                let clip = to_clip * vec4<f32>(at - cam, 1.0);
                if clip.w < 0.3 {
                    continue;
                }
                let ndc = clip.xyz / clip.w;
                let spot = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
                let d = length((input.uv - spot) * frame.resolution);
                // A firefly is a point of light, not a ball: its size is held to a few pixels, and the
                // far ones are faint, so none pulls the eye from across the field.
                let size = 0.045 * px_per_block / clip.w;
                let radius = clamp(size, 0.6, 3.0);
                let spread = min(3.0 * radius, 10.0);
                if d > spread * 2.5 + 2.0 {
                    continue;
                }
                // Behind a wall, a hill or a tree: hidden (depth is reversed, larger is nearer).
                if any(spot < vec2<f32>(0.0)) || any(spot > vec2<f32>(1.0)) || depth_at(spot) > ndc.z {
                    continue;
                }
                // Each blinks on its own clock: a quick glow, then a long fade, then a pause.
                let phase = fract(t * (0.16 + 0.14 * h2.y) + h2.z * 7.0);
                let pulse = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.08, 0.5, phase));
                let far = 1.0 / (1.0 + pow(clip.w / 10.0, 2.0));
                let tiny = clamp(size * size, 0.15, 1.0);
                let level = (0.08 + pulse) * near_height * far * tiny;
                let core = exp(-d * d / (radius * radius));
                let halo = exp(-d * d / (spread * spread)) * 0.08;
                add += tone * (core * 3.0 + halo) * level;
            }
        }
    }
    return vec4<f32>(colour + add * amount, 1.0);
}
