// The picture put together: the light shafts (blurred up from half size), the three layers of
// glow, then the grade: vivid colour, cool shadows and warm light, and a light vignette.

fn shafts_at(uv: vec2<f32>) -> vec3<f32> {
    let px = 2.0 / frame.resolution;
    var sum = textureSampleLevel(shafts, linear_sampler, uv, 0.0).rgb * 0.36;
    sum += textureSampleLevel(shafts, linear_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb * 0.16;
    sum += textureSampleLevel(shafts, linear_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb * 0.16;
    sum += textureSampleLevel(shafts, linear_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb * 0.16;
    sum += textureSampleLevel(shafts, linear_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb * 0.16;
    return sum;
}

// The contact shade (post/ssao.wgsl), blurred up from half size.
fn ao_at(uv: vec2<f32>) -> f32 {
    let px = 2.0 / frame.resolution;
    var sum = textureSampleLevel(ao_target, linear_sampler, uv, 0.0).r * 0.4;
    sum += textureSampleLevel(ao_target, linear_sampler, uv + vec2<f32>(px.x, px.y) * 0.75, 0.0).r * 0.15;
    sum += textureSampleLevel(ao_target, linear_sampler, uv + vec2<f32>(-px.x, px.y) * 0.75, 0.0).r * 0.15;
    sum += textureSampleLevel(ao_target, linear_sampler, uv + vec2<f32>(px.x, -px.y) * 0.75, 0.0).r * 0.15;
    sum += textureSampleLevel(ao_target, linear_sampler, uv - vec2<f32>(px.x, px.y) * 0.75, 0.0).r * 0.15;
    return sum;
}

// The first bounce (post/bounce.wgsl), blurred up from half size.
fn bounce_at(uv: vec2<f32>) -> vec3<f32> {
    let px = 2.0 / frame.resolution;
    var sum = textureSampleLevel(bounce_target, linear_sampler, uv, 0.0).rgb * 0.28;
    sum += textureSampleLevel(bounce_target, linear_sampler, uv + vec2<f32>(px.x, px.y) * 1.5, 0.0).rgb * 0.18;
    sum += textureSampleLevel(bounce_target, linear_sampler, uv + vec2<f32>(-px.x, px.y) * 1.5, 0.0).rgb * 0.18;
    sum += textureSampleLevel(bounce_target, linear_sampler, uv + vec2<f32>(px.x, -px.y) * 1.5, 0.0).rgb * 0.18;
    sum += textureSampleLevel(bounce_target, linear_sampler, uv - vec2<f32>(px.x, px.y) * 1.5, 0.0).rgb * 0.18;
    return sum;
}

// The colour of the moment: how much colour the picture carries (x) and the cast of its light
// (yzw), blended from what the frame says about where and when the eye is. Each place gets its own
// palette: a vivid clear day, a golden hour richer still, a quiet blue night, a grey-teal rain, the
// washed brilliance after it, a crisp cold blue in the snow, warm torchlight against cool shade
// underground, a green-blue underwater, the Nether's reds and the End's violets.
struct Grade {
    saturation: f32,
    tint: vec3<f32>,
}

fn scene_grade() -> Grade {
    var g = Grade(1.0, vec3<f32>(1.0));
    if frame.dimension == -1 {
        // The Nether's biomes each have their own fog colour (crimson red, warped teal, soul sand
        // blue, basalt grey, the wastes' orange): the picture takes a share of its hue.
        let fog = frame.fog_color / max(max(frame.fog_color.r, max(frame.fog_color.g, frame.fog_color.b)), 0.001);
        let hue_tint = mix(vec3<f32>(1.0), fog, 0.35);
        g.saturation = 1.14;
        g.tint = hue_tint * vec3<f32>(1.03, 0.98, 0.96);
        g.tint = g.tint / max(luma(g.tint), 0.001);
        return g;
    }
    if frame.dimension == 1 {
        g.saturation = 1.12;
        g.tint = vec3<f32>(1.02, 0.96, 1.06);
        return g;
    }
    if frame.eye_in == 1u {
        g.saturation = 1.08;
        g.tint = vec3<f32>(0.94, 1.02, 1.04);
        return g;
    }
    let day = day_amount();
    let dusk = twilight_amount();
    let night = night_amount();
    let rain = wx_overcast();
    let after = after_rain();
    let cold = clamp(sky_memory[0], 0.0, 1.0);
    // Underground and indoors: little sky round the eye.
    let inside = 1.0 - smoothstep(0.25, 0.75, frame.eye_light_smooth.y);

    // How much colour: a little more on clear days, more at the golden hour and after rain, less
    // in rain and by night (the eye sees less colour in the dark), a touch less in the snow.
    var sat = 1.08 * day + 0.86 * night;
    sat = mix(sat, 1.2, dusk * (1.0 - rain));
    sat = mix(sat, 0.84, rain);
    sat += 0.08 * after;
    sat = mix(sat, sat * 0.95, cold);
    // Each land its palette: sunlit sand and savanna rich and warm, jungles and swamps lush.
    sat += 0.06 * biome_arid() * day + 0.08 * biome_humid() * day;
    sat = mix(sat, 1.1, inside);
    g.saturation = sat;

    // The light's cast: warm sun by day, gold at dusk, moon-blue at night, grey-teal in rain, cold
    // blue in the snow, neutral underground (the torches bring their own colour).
    var hue_cast = mix(vec3<f32>(0.94, 0.97, 1.08), vec3<f32>(1.03, 1.0, 0.96), day);
    hue_cast = mix(hue_cast, vec3<f32>(1.08, 0.99, 0.9), dusk * (1.0 - rain));
    hue_cast = mix(hue_cast, vec3<f32>(0.96, 1.0, 1.03), rain);
    hue_cast = mix(hue_cast, hue_cast * vec3<f32>(1.05, 1.0, 0.92), biome_arid() * day * (1.0 - rain));
    hue_cast = mix(hue_cast, hue_cast * vec3<f32>(0.97, 1.03, 0.97), biome_humid() * day);
    hue_cast = mix(hue_cast, vec3<f32>(0.96, 0.99, 1.06), cold * day * 0.8);
    hue_cast = mix(hue_cast, vec3<f32>(1.0), inside * 0.7);
    // The cast moves the colour, not the brightness.
    g.tint = hue_cast / max(luma(hue_cast), 0.001);
    return g;
}

fn post(input: PostInput) -> vec4<f32> {
    load_weather();
    var c = input.color.rgb;
    if mirror_terrain() && input.depth > 0.0 {
        let s = surface_at(vec2<i32>(input.uv * frame.resolution));
        // The terrain's smoothness, with 2 added on bare metal (material.wgsl).
        let is_metal = s.smoothness >= 1.5;
        let smooth_ = s.smoothness - select(0.0, 2.0, is_metal);
        if s.present && smooth_ > 0.35 {
            let p = view_position(input.uv, input.depth);
            let v = normalize(p - eye_offset());
            let n = normalize(s.normal);
            // Metals mirror much of the light even face-on; water, puddles and wet stone little,
            // until the view grows shallow.
            let f0 = select(0.03, 0.6, is_metal);
            let f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(-v, n), 0.0, 1.0), 5.0);
            let strength = smoothstep(0.35, 0.85, smooth_) * f;
            if strength > 0.01 && length(p) < 72.0 {
                let hit = screen_mirror(p, n, reflect(v, n), scene_depth);
                if hit.z > 0.0 {
                    var reflected = textureSampleLevel(previous, linear_sampler, hit.xy, 0.0).rgb;
                    // A metal tints what it mirrors with its own colour.
                    if is_metal {
                        let hue = c / max(max(c.r, max(c.g, c.b)), 0.0001);
                        reflected *= mix(vec3<f32>(1.0), hue, 0.6);
                    }
                    c = mix(c, reflected, clamp(strength * hit.z, 0.0, 0.9));
                }
            }
        }
    }
    let path_mode = ray_mode == 2u && frame.has_ray_tracing != 0u && frame.ray_distance > 1.0;
    // The first bounce, on Max: the light gathered round the point, coloured by the surface's own
    // albedo (its lightness kept by the terrain, its hue the picture's), and weighed by how enclosed
    // the point is: under the open sky the sky's light already stands for it.
    if (max_quality() || path_mode) && bounce_light > 0.0 && input.depth > 0.0 {
        let s = surface_at(vec2<i32>(input.uv * frame.resolution));
        if s.present {
            let hue = c / max(max(c.r, max(c.g, c.b)), 0.0001);
            let albedo = hue * (surface_albedo(s.data) / max(luma(hue), 0.001));
            let sky = surface_sky(s.data);
            let enclosed = 1.0 - 0.85 * sky * sky;
            var indirect: vec3<f32>;
            if path_mode {
                let z = (frame.projection_inverse * vec4<f32>(input.uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0), input.depth, 1.0)).w;
                indirect = path_upsample(input.uv, 1.0 / max(z, 1e-6));
            } else {
                indirect = bounce_at(input.uv) * enclosed;
            }
            c += indirect * albedo * clamp(bounce_light, 0.0, 2.0);
        }
    }
    if ambient_occlusion > 0.0 && input.depth > 0.0 {
        c *= mix(1.0, ao_at(input.uv), clamp(ambient_occlusion, 0.0, 2.0) * 0.5);
    }
    if shafts_enabled() {
        c += shafts_at(input.uv);
    }
    if glow > 0.0 {
        let near = textureSampleLevel(bloom_half, linear_sampler, input.uv, 0.0).rgb;
        let soft = textureSampleLevel(bloom_quarter, linear_sampler, input.uv, 0.0).rgb;
        let wide = textureSampleLevel(bloom_wide, linear_sampler, input.uv, 0.0).rgb;
        c += (near * 0.25 + soft * 0.4 + wide * 0.6) * glow;
    }
    c += sun_flare(input.uv);
    // The moment's palette (scene_grade): its cast, then its colour amount with the option's.
    let grade = scene_grade();
    c *= grade.tint;
    let amount = saturation * grade.saturation;
    // Vivid: the colour pushed away from grey, the dull colours more than the bright ones.
    let l = luma(c);
    let chroma = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
    let push = amount + (amount - 1.0) * 0.6 * (1.0 - smoothstep(0.0, max(l, 0.0001) * 1.2, chroma));
    c = max(mix(vec3<f32>(l), c, push), vec3<f32>(0.0));
    // Vibrance: the duller colours (a hazy sky, foliage in shade, water) gain colour, the ones
    // already strong stay as they are, so nothing turns loud; less of it by night.
    let top = max(max(c.r, c.g), c.b);
    let sat = (top - min(min(c.r, c.g), c.b)) / max(top, 0.0001);
    let vib = 0.24 * (1.0 - sat) * (0.35 + 0.65 * day_amount());
    c = max(mix(vec3<f32>(luma(c)), c, 1.0 + vib), vec3<f32>(0.0));
    // Cool shadows, warm light: a gentle split tone, stronger by day.
    let tone = smoothstep(0.0, 0.8, l / (1.0 + l));
    let split = mix(vec3<f32>(0.95, 0.98, 1.06), vec3<f32>(1.04, 1.0, 0.95), tone);
    c *= mix(vec3<f32>(1.0), split, 0.5 + 0.5 * day_amount());
    // A light vignette.
    let aspect = frame.resolution.x / frame.resolution.y;
    let v = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
    c *= 1.0 - smoothstep(0.55, 1.15, v) * 0.25;
    return vec4<f32>(c, 1.0);
}
