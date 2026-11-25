// How a surface is lit, shared by the terrain and the entity stages: the sun (the moon by night)
// through crisp shadows, coloured where the light passes through glass or water, the sky's light,
// block light tinted by the lights round it, and what the surface gives off itself.

// The pixel being shaded, set by the material stage, for the shadow edge's dither (-1: unknown,
// then the world position is used).
var<private> shadow_pixel: vec2<f32> = vec2<f32>(-1.0);

// How much of the light reaches the camera-relative `position` on a surface facing `normal`: 1 lit,
// 0 in shadow, and the colour of the glass or water the light came through in between.
fn shadow_at(position: vec3<f32>, normal: vec3<f32>, facing: f32) -> vec3<f32> {
    if frame.has_shadow == 0u {
        return vec3<f32>(1.0);
    }
    let dist = length(position);
    // Off the surface by about a texel and a half, more on faces turned from the light and far out,
    // where a texel covers more ground.
    let bias = frame.shadow_center_texel * (0.9 + 2.2 * (1.0 - facing)) * (1.0 + 2.0 * dist / max(frame.shadow_distance, 1.0));
    let p = shadow_position(position + normal * bias);
    if any(p.xy <= vec2<f32>(0.0)) || any(p.xy >= vec2<f32>(1.0)) || p.z >= 1.0 {
        return vec3<f32>(1.0);
    }
    var solid = 0.0;
    var through = 0.0;
    // Far off a soft edge is narrower than a pixel: the crisp filter does there.
    if quality == 0u {
        // Low: one compare (itself a 2x2 filtered one).
        solid = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z);
        through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z);
    } else if !max_quality() || soft_shadows <= 0.0 || dist > 40.0 {
        // Crisp: four compares a third of a texel apart, each itself a 2x2 filtered one.
        let t = 0.35 / max(frame.shadow_resolution, 1.0);
        for (var i = 0; i < 4; i++) {
            let o = vec2<f32>(select(-t, t, (i & 1) == 1), select(-t, t, i >= 2));
            solid += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + o, p.z);
            through += textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy + o, p.z);
        }
        solid *= 0.25;
        through *= 0.25;
    } else {
        let soft = soft_shadow_at(position, p);
        solid = soft.x;
        through = soft.y;
    }
    var tint = vec3<f32>(1.0);
    if solid - through > 0.01 {
        let size = vec2<f32>(textureDimensions(shadow_color));
        let c = textureLoad(shadow_color, vec2<i32>(p.xy * size), 0);
        // Stained glass colours the light; water dims and blues it, and its ripples focus it into
        // a wandering web of light (caustics) on what lies below.
        if c.a >= 0.999 {
            let world = position + frame.camera_position;
            // The depth's own loss of light is the water surface's (material.wgsl): here the light
            // only takes a little of the water's hue.
            let hue = c.rgb / max(max(c.r, max(c.g, c.b)), 0.01);
            tint = mix(vec3<f32>(1.0), hue, 0.3) * 0.85 * mix(1.0, caustic_pattern(world), caustics_amount() * 0.6);
        } else {
            tint = c.rgb;
        }
    }
    let lit = vec3<f32>(through) + (solid - through) * tint;
    // Past the map's reach, everything is lit (the sky light still darkens what is covered).
    let fade = smoothstep(0.85, 1.0, dist / max(frame.shadow_distance, 1.0));
    return mix(lit, vec3<f32>(1.0), fade);
}

// A shadow whose edge widens with the distance to what casts it (the sun is a disc, not a point):
// sharp where a trunk meets the ground, soft at the end of a long shadow, the canopy's shade
// dappled. `p` is the point in the shadow map (after the bias), `position` camera-relative. Returns
// how lit the point is through solid things (x) and through solid and translucent things (y).
fn soft_shadow_at(position: vec3<f32>, p: vec3<f32>) -> vec2<f32> {
    let res = max(frame.shadow_resolution, 1.0);
    let texel = 1.0 / res;
    // 0. A cheap probe first: the centre and four points at the widest edge the filter could ask
    // for. Where all five agree (wholly lit, or wholly in shade: most of the picture) there is no
    // edge near, and the point is done.
    let reach = max(0.45 / max(frame.shadow_center_texel * res, 1e-4), texel * 2.0);
    var probe = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z);
    probe += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>(reach, 0.0), p.z);
    probe += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy - vec2<f32>(reach, 0.0), p.z);
    probe += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + vec2<f32>(0.0, reach), p.z);
    probe += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy - vec2<f32>(0.0, reach), p.z);
    if probe >= 4.999 {
        let through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z);
        return vec2<f32>(1.0, through);
    }
    if probe <= 0.001 {
        return vec2<f32>(0.0, 0.0);
    }
    // How far one block reaches in the map here (its distortion included), and how many blocks one
    // unit of the map's depth spans along the light.
    let l = frame.light_direction;
    let side = normalize(cross(l, select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(l.y) > 0.95)));
    let uv_per_block = max(length(shadow_position(position + side).xy - shadow_position(position).xy), texel * 0.1);
    let m = frame.shadow_view_proj;
    let blocks_per_depth = 1.0 / max(abs(dot(vec3<f32>(m[0][2], m[1][2], m[2][2]), l)), 1e-5);
    // The sun's width, made a little wider than the real one for a softer, friendlier light.
    let spread = 0.03 * clamp(soft_shadows, 0.0, 2.0);
    let max_blocks = 0.45;
    // A dither turned per texel of the world, so the pattern sits still on the surface.
    let world = position + frame.camera_position;
    var turn = hash13(floor(world * 16.0)) * 6.2831853;
    if shadow_pixel.x >= 0.0 {
        turn = fract(52.9829189 * fract(dot(floor(shadow_pixel), vec2<f32>(0.06711056, 0.00583715)))) * 6.2831853;
    }
    let c = cos(turn);
    let s = sin(turn);
    // 1. Look for what casts the shadow: the mean depth of the blockers round the point.
    let search = max(max_blocks * uv_per_block, texel * 2.0);
    var blockers = 0.0;
    var found = 0.0;
    for (var i = 0; i < 4; i++) {
        let a = (f32(i) + 0.5) / 4.0;
        let v = vec2<f32>(cos(f32(i) * 2.3999632), sin(f32(i) * 2.3999632)) * sqrt(a);
        let o = vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y) * search;
        let d = textureLoad(shadow_map, vec2<i32>(clamp((p.xy + o) * res, vec2<f32>(0.0), vec2<f32>(res - 1.0))), 0);
        if d < p.z {
            blockers += d;
            found += 1.0;
        }
    }
    // Nothing casts a shadow here, or everything round does: no edge to soften, so skip the filter
    // (most of the picture). Glass and water still tint the light through the translucent map.
    if found == 0.0 {
        let through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z);
        return vec2<f32>(1.0, through);
    }
    if found == 4.0 {
        return vec2<f32>(0.0, 0.0);
    }
    // 2. The edge's width from how far the blocker is; at least the crisp filter's own.
    var radius = texel * 0.5;
    {
        let gap = (p.z - blockers / found) * blocks_per_depth;
        radius = clamp(gap * spread, 0.0, max_blocks) * uv_per_block;
        radius = max(radius, texel * 0.5);
    }
    // 3. Filter over that width: a turned spiral of 2x2 filtered compares.
    let taps = 8;
    var solid = 0.0;
    var through = 0.0;
    for (var i = 0; i < taps; i++) {
        let a = (f32(i) + 0.5) / f32(taps);
        let v = vec2<f32>(cos(f32(i) * 2.3999632), sin(f32(i) * 2.3999632)) * sqrt(a);
        let o = vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y) * radius;
        solid += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + o, p.z);
        through += textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy + o, p.z);
    }
    return vec2<f32>(solid, through) / f32(taps);
}

// How open a point is to the sun's light, before its shadow: within the shadow map's reach the
// map decides (a sunbeam through a window lights the floor inside), and only a point that sees no
// sky at all (a sealed cave) is kept dark; past the map's reach, only open ground is lit.
fn sun_open(position: vec3<f32>, sky: f32) -> f32 {
    let gate = smoothstep(0.55, 0.97, sky);
    if frame.has_shadow == 0u {
        return gate;
    }
    let inside_map = 1.0 - smoothstep(0.75, 0.9, length(position.xz) / max(frame.shadow_distance, 1.0));
    return max(gate, inside_map * smoothstep(0.02, 0.12, sky));
}

// The lit colour of a surface of colour `albedo` in the Overworld. `light` is block and sky light
// (0..1), `ao` the ambient occlusion, `emission` how much light it gives off, `coloured` the frame's
// coloured lights at it, `foliage` 1 for leaves and plants, which light lets through.
fn light_surface(
    albedo: vec3<f32>,
    normal: vec3<f32>,
    position: vec3<f32>,
    light: vec2<f32>,
    ao: f32,
    emission: f32,
    coloured: vec3<f32>,
    foliage: f32,
) -> vec3<f32> {
    let facing = dot(normal, frame.light_direction);
    var sun_shadow = vec3<f32>(1.0);
    if sun_open(position, light.y) > 0.0 {
        sun_shadow = shadow_at(position, normal, max(facing, 0.0));
    }
    return light_surface_shadowed(albedo, normal, position, light, ao, emission, coloured, foliage, sun_shadow);
}

// The same, with the sun's shadow at the point (`shadow_at`) already found, so a caller that needs
// it again (for a glossy highlight) looks it up only once.
fn light_surface_shadowed(
    albedo: vec3<f32>,
    normal: vec3<f32>,
    position: vec3<f32>,
    light: vec2<f32>,
    ao: f32,
    emission: f32,
    coloured: vec3<f32>,
    foliage: f32,
    sun_shadow: vec3<f32>,
) -> vec3<f32> {
    let block = light.x;
    let sky = light.y;
    let facing = dot(normal, frame.light_direction);
    // Leaves and plants glow when the light is behind them, and are lit softly from every side.
    let wrap = mix(max(facing, 0.0), clamp((facing + 0.5) / 1.5, 0.0, 1.0), foliage);
    var direct = vec3<f32>(0.0);
    // Only where the sky is open: no sunbeams in caves past the shadow map's reach.
    let open = sun_open(position, sky);
    if wrap > 0.0 && open > 0.0 {
        direct = direct_light() * wrap * sun_shadow * open * cloud_shadow(position);
    }
    if foliage > 0.0 && facing < 0.0 && open > 0.0 {
        direct += direct_light() * max(-facing, 0.0) * 0.25 * shadow_at(position - normal * 0.9, -normal, 1.0) * open * cloud_shadow(position);
    }
    // The sky's light, more from above than from the side, and a little bounce from the ground.
    let hemi = 0.62 + 0.38 * normal.y;
    let ambient = sky_ambient() * hemi * sky * sky * mix(1.0, ao, 0.85);
    // Block light, falling off fast as vanilla's does, tinted by the lights nearby.
    let torch = torch_light(position, block) * mix(1.0, ao, 0.6);
    // Never quite black, a little more with the Brightness option and night vision.
    // The game's Brightness option nudges it only a little: at Bright, nights must stay night.
    let least = rgb(0.45, 0.5, 0.62) * (0.008 + 0.008 * frame.brightness) + vec3<f32>(frame.night_vision * 0.35);
    // Fireflies and held torches (dynamic and particle lights).
    let glowing = coloured * 1.6;
    return albedo * (direct + ambient + torch + least + glowing) + albedo * emission * 1.4;
}

// The block light reaching camera-relative `position` with block light level `block` (0..1): the
// nearby lights' own colour as soon as any of it reaches (at the brightness of the warm default,
// so a blue soul fire paints the stone blue rather than a washed lavender), falling off fast as
// vanilla's does. Blue fires burn at a lower level and get a little back.
fn torch_light(position: vec3<f32>, block: f32) -> vec3<f32> {
    let near = block_light_color(position);
    let warm = rgb(1.0, 0.74, 0.48);
    let raw = near.rgb / max(max(near.r, max(near.g, near.b)), 0.0001);
    let hue = max(mix(vec3<f32>(luma(raw)), raw, 1.25), vec3<f32>(0.0));
    let reach = smoothstep(0.02, 0.25, near.a);
    let tint = mix(warm, hue * (luma(warm) / max(luma(hue), 0.001)), reach);
    let cold = reach * smoothstep(0.3, 0.6, near.b - near.r);
    let block_amount = (pow(block, 2.4) * 1.5 + block * 0.05) * mix(1.0, 1.6, cold);
    return tint * block_amount;
}

// The same surface in the Nether or the End: vanilla's light, a little richer.
fn light_elsewhere(albedo: vec3<f32>, lightmap: vec3<f32>, shade: f32, emission: f32, coloured: vec3<f32>) -> vec3<f32> {
    return albedo * (lightmap * shade * 1.1 + coloured * 1.4) + albedo * emission * 0.8;
}

// The sun's (the moon's) highlight on a glossy surface: a GGX lobe for `smoothness` 0..1 and
// reflectance `f0`, times the light's colour and shadow (`lit_by`). `view` points from the eye.
fn sun_specular(normal: vec3<f32>, view: vec3<f32>, smoothness: f32, f0: f32, lit_by: vec3<f32>) -> vec3<f32> {
    let l = frame.light_direction;
    let h = normalize(l - view);
    let n_h = max(dot(normal, h), 0.0);
    let n_l = max(dot(normal, l), 0.0);
    let n_v = max(dot(normal, -view), 0.001);
    let rough = max(1.0 - smoothness, 0.04);
    let a = rough * rough;
    let a2 = a * a;
    let d = a2 / (PI * pow(n_h * n_h * (a2 - 1.0) + 1.0, 2.0));
    let f = f0 + (1.0 - f0) * pow(1.0 - max(dot(h, -view), 0.0), 5.0);
    let k = a * 0.5;
    let g = n_l / (n_l * (1.0 - k) + k) * n_v / (n_v * (1.0 - k) + k);
    return lit_by * d * f * g / (4.0 * n_v + 0.001) * PI;
}

// The sky a glossy surface mirrors along `r`, dark where it lies under cover (`sky` light 0..1).
fn sky_mirror(r: vec3<f32>, sky: f32) -> vec3<f32> {
    let open = smoothstep(0.4, 0.95, sky);
    return atmosphere(normalize(vec3<f32>(r.x, abs(r.y) + 0.02, r.z))) * open;
}
