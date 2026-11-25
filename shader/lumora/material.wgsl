// Terrain: lit by `light_surface` (lighting.wgsl), wet in the rain (darker, glossy, with puddles
// that mirror the sky and ripple under the drops), snowed on in the cold, LabPBR normal and
// specular maps where a resource pack ships them, glowing ores and light blocks, and water of its
// own (refraction, colour by depth, foam, ripples, reflections), then the pack's fog.

// Material ids from the manifest.
const LEAVES: u32 = 10u;
const PLANTS: u32 = 11u;
const WATER: u32 = 12u;
const TALL_PLANTS: u32 = 13u;
const DOUBLE_LOW: u32 = 14u;
const DOUBLE_HIGH: u32 = 15u;
const ORES: u32 = 16u;
const STONE: u32 = 20u;
const WOOD: u32 = 21u;
const METAL: u32 = 22u;
const GLASS: u32 = 23u;

// The height of the water's ripples at world point `p`, for its normal.
fn ripples(p: vec2<f32>, t: f32) -> f32 {
    let a = noise3(vec3<f32>(p * 0.55 + vec2<f32>(t * 0.35, t * 0.18), t * 0.2));
    let b = noise3(vec3<f32>(p * 1.3 - vec2<f32>(t * 0.25, -t * 0.4), 3.0 + t * 0.3));
    return a * 0.65 + b * 0.35;
}

// Rings spreading from raindrops on water and puddles at world column `p`: the slope they give the
// surface (x along east, y along south). Each cell of the surface gets a drop on its own clock.
fn rain_rings(p: vec2<f32>) -> vec2<f32> {
    if wx_rain() <= 0.02 {
        return vec2<f32>(0.0);
    }
    var slope = vec2<f32>(0.0);
    for (var layer = 0; layer < 2; layer++) {
        let q = p * 1.7 + vec2<f32>(f32(layer) * 3.7, f32(layer) * 1.3);
        let cell = floor(q);
        let h = hash12(cell + f32(layer) * 17.0);
        let phase = fract(frame.time * (0.9 + 0.5 * h) + h * 7.0);
        let centre = vec2<f32>(hash12(cell + 3.1), hash12(cell + 8.7)) * 0.5 + 0.25;
        let v = fract(q) - centre;
        let r = length(v);
        let x = r - phase * 0.42;
        let ring = sin(x * 55.0) * exp(-x * x * 260.0) * (1.0 - phase) * (1.0 - phase);
        slope += v / max(r, 0.0001) * ring;
    }
    return slope * 0.35 * wx_overcast();
}

// The camera-relative point that the opaque picture holds at screen point `uv` and depth `depth`.
fn opaque_point(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let ndc = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let v = frame.projection_inverse * ndc;
    return (frame.view_inverse * vec4<f32>(v.xyz / v.w, 0.0)).xyz;
}

// The sky along the mirrored ray `r`, clouds and all: looked up in the map sky_map.wgsl makes before
// the world draws (by azimuth, and the square root of the height above the horizon).
fn mirrored_sky(r: vec3<f32>) -> vec3<f32> {
    let d = normalize(vec3<f32>(r.x, abs(r.y) + 0.002, r.z));
    let u = fract(atan2(d.z, d.x) / 6.2831853);
    let v = sqrt(clamp(d.y, 0.0, 1.0));
    return textureSampleLevel(reflected_sky, reflection_sampler, vec2<f32>(u, v), 0.0).rgb;
}

// Translucent geometry can sample the already-drawn opaque scene without feedback.
fn transparent_mirror(input: MaterialInput, n: vec3<f32>, r: vec3<f32>, fallback: vec3<f32>) -> vec3<f32> {
    var screen_hit = vec3<f32>(0.0);
    if mirror_water() {
        screen_hit = screen_mirror(input.position, n, r, opaque_depth);
    }
    var reflected = fallback;
    if screen_hit.z < 0.995 && ray_ready() {
        reflected = ray_mirror(input.position, n, r, reflected);
    }
    if screen_hit.z > 0.0 {
        let uv = vec2<i32>(screen_hit.xy * vec2<f32>(textureDimensions(opaque_color)));
        reflected = mix(reflected, textureLoad(opaque_color, uv, 0).rgb, screen_hit.z);
    }
    return reflected;
}

fn water(input: MaterialInput, lit: vec3<f32>) -> vec4<f32> {
    let view = normalize(input.position);
    let world = input.position.xz + frame.camera_position.xz;
    let dist = length(input.position);
    var n = input.normal;
    let from_above = n.y > 0.5;
    if from_above {
        // Gentle ripples on the surface near the camera, smoothed away far off, and raindrops.
        let e = 0.15;
        let h = ripples(world, frame.time);
        let dx = ripples(world + vec2<f32>(e, 0.0), frame.time) - h;
        let dz = ripples(world + vec2<f32>(0.0, e), frame.time) - h;
        let calm = 1.0 - smoothstep(16.0, 64.0, dist);
        let drops = rain_rings(world) * (1.0 - smoothstep(8.0, 32.0, dist)) * clamp(rain_effects, 0.0, 2.0);
        // Far off the small ripples are too fine to see, but the larger swell still breaks up
        // what the water mirrors, so the far lake keeps a texture instead of turning to glass.
        let far = 1.0 - calm;
        var sx = 0.0;
        var sz = 0.0;
        if far > 0.01 {
            let ef = 0.8;
            let hf = ripples(world * 0.22, frame.time * 0.6);
            sx = (ripples(world * 0.22 + vec2<f32>(ef * 0.22, 0.0), frame.time * 0.6) - hf) / ef;
            sz = (ripples(world * 0.22 + vec2<f32>(0.0, ef * 0.22), frame.time * 0.6) - hf) / ef;
        }
        // Seen at a slant, a small tilt swings the mirrored ray between cloud and blue sky and the
        // water breaks into repeated bright cells: the ripples flatten as the view gets lower.
        let slant = mix(0.35, 1.0, smoothstep(0.03, 0.35, abs(view.y)));
        let near_amp = 1.3 * slant;
        let far_amp = 0.6;
        n = normalize(vec3<f32>((-dx * near_amp - drops.x) * calm - sx * far_amp * far, 1.0, (-dz * near_amp - drops.y) * calm - sz * far_amp * far));
    }
    let r = reflect(view, n);
    let cos_v = max(dot(-view, n), 0.0);
    // At a grazing angle the rough surface never mirrors fully: some of the water's own colour stays.
    let fresnel = (0.02 + 0.98 * pow(1.0 - cos_v, 5.0)) * mix(1.0, 0.72, smoothstep(16.0, 96.0, dist));
    // The sky it mirrors: dark where the water lies under cover.
    let open = smoothstep(0.4, 0.95, input.light.y);
    var mirrored = mirrored_sky(r) * open;
    // The world mirrored in the water (the game's water mirror, at the water level round the
    // camera): trees, hills and houses on the far bank. Where the mirror shows the game's own sky
    // (a blend of its fog and sky colours) the pack's sky goes in its place.
    let level = input.position.y + frame.camera_position.y;
    if water_reflections && frame.has_reflection == 1u && abs(level - frame.water_plane) < 0.6 {
        // The waves smear the mirrored bank more the flatter the view.
        let smear = 0.018 * min(1.0 / max(cos_v, 0.12), 4.0);
        let uv = clamp(input.screen + vec2<f32>(n.x, n.z * 0.5) * smear, vec2<f32>(0.001), vec2<f32>(0.999));
        let m = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
        let a = frame.fog_color;
        let ab = frame.sky_color - a;
        let along = clamp(dot(m - a, ab) / max(dot(ab, ab), 0.00001), 0.0, 1.0);
        let off = length(m - (a + ab * along)) / (luma(m) + 0.05);
        let sky_like = 1.0 - smoothstep(0.05, 0.18, off);
        mirrored = mix(m * 0.9, mirrored, sky_like);
    }
    if water_reflections && from_above && (mirror_water() || ray_ready()) {
        mirrored = transparent_mirror(input, n, r, mirrored);
    }
    // The sun's (or the moon's) glint.
    // The sun's glint: one sharp spot near by, a field of sparkles on the far water; none seen
    // from below the surface.
    let sparkle = smoothstep(16.0, 96.0, dist);
    let glint = pow(max(dot(r, frame.light_direction), 0.0), mix(260.0, 70.0, sparkle)) * mix(6.0, 2.5, sparkle)
        * select(0.0, 1.0, from_above);
    let lit_by = direct_light() * shadow_at(input.position, input.normal, 1.0) * open;
    if !water_refraction {
        let body = lit * 0.75;
        let colour = mix(body, mirrored, fresnel) + lit_by * glint;
        let alpha = clamp(mix(input.albedo.a * 0.85, 1.0, fresnel), 0.0, 1.0);
        return vec4<f32>(colour, alpha);
    }

    // What lies behind the surface, bent by the ripples: the bed, the fish, the far bank.
    let size = frame.resolution;
    let here = frame.projection * frame.view * vec4<f32>(input.position, 1.0);
    let here_depth = here.z / here.w;
    let bend = vec2<f32>(n.x, n.z) * 0.05 * (1.0 - smoothstep(4.0, 48.0, dist));
    var suv = clamp(input.screen + bend, vec2<f32>(0.001), vec2<f32>(0.999));
    var behind = textureLoad(opaque_depth, vec2<i32>(suv * size), 0);
    // A bent ray landing on something in front of the water (a reed, the bank) looks straight.
    if behind > here_depth {
        suv = input.screen;
        behind = textureLoad(opaque_depth, vec2<i32>(suv * size), 0);
    }
    let seen = textureLoad(opaque_color, vec2<i32>(suv * size), 0).rgb;
    var thickness = 48.0;
    if behind > 0.0 {
        thickness = max(length(opaque_point(suv, behind)) - dist, 0.0);
    }
    // How deep the water is straight down, not along the slanting view: shallow water seen from the
    // side stays shallow (turquoise, foamy).
    let vdepth = thickness * abs(view.y);
    if !from_above {
        // Seen from below: the air above shows straight through, the murk does the rest.
        thickness = 0.0;
    }
    // Light lost on its way through the water (reds first), and what the water itself scatters
    // back: its own biome-tinted colour, lit as the surface is.
    // Water is a little cloudy as well as blue: a neutral haze hides the bed as it deepens (the
    // Water clarity option), while the shallows at the shore stay clear.
    let murk = 0.14 * (2.0 - clamp(water_clarity, 0.0, 2.0));
    let through = exp(-thickness * (water_absorption() + vec3<f32>(murk)));
    // Deep water scatters back less: shallows stay light, the deep goes dark.
    let scatter = lit * 0.62 * mix(1.15, 0.55, 1.0 - exp(-vdepth * 0.18));
    var body = seen * through + scatter * (1.0 - through);
    // Foam where the water is shallow against the shore, broken up and drifting.
    if from_above {
        let shore = 1.0 - smoothstep(0.0, 0.55, vdepth);
        let w = world + vec2<f32>(frame.time * 0.12, frame.time * 0.07);
        let froth = smoothstep(0.45, 0.8, noise2(w * 3.1) * 0.6 + noise2(w * 7.3) * 0.4 + shore * 0.35);
        let light = sky_ambient() * input.light.y * input.light.y + lit_by + rgb(1.0, 0.74, 0.48) * pow(input.light.x, 2.4);
        body = mix(body, light * 0.85, shore * froth * 0.8 * (1.0 - smoothstep(24.0, 64.0, dist)));
    }
    if !from_above {
        // From below, the sky shows only through a round window overhead; past its edge the surface
        // mirrors the water itself (total internal reflection), dark and blue-green.
        // The surface seen from below ripples too, so the window's rim wobbles as it does in a pool.
        let h = ripples(world, frame.time);
        let rx = ripples(world + vec2<f32>(0.15, 0.0), frame.time) - h;
        let rz = ripples(world + vec2<f32>(0.0, 0.15), frame.time) - h;
        let below_n = normalize(vec3<f32>(rx * 1.1, -1.0, rz * 1.1));
        // The window's rim is soft (light bends more and more toward it), and what shows through it
        // is dimmed and cooled by the water above the eye.
        let incidence = abs(dot(view, below_n));
        let window = smoothstep(0.6, 0.74, incidence);
        let inside = lit * 0.3;
        let through_sky = body * mix(vec3<f32>(0.75, 0.88, 0.95), vec3<f32>(1.0), window);
        return vec4<f32>(mix(inside, through_sky, window), 1.0);
    }
    let colour = mix(body, mirrored, fresnel) + lit_by * glint;
    return vec4<f32>(colour, 1.0);
}

fn material(input: MaterialInput) -> Surface {
    load_weather();
    shadow_pixel = input.screen * frame.resolution;
    var albedo = input.albedo.rgb * input.tint.rgb;
    let world = input.position + frame.camera_position;
    // Screen-space slopes, taken first (they need every pixel of the quad): how the texture's
    // lightness and the block light change across the surface, turned into world directions.
    let dx_uv = dpdx(input.uv);
    let dy_uv = dpdy(input.uv);
    var texel_colour = input.albedo.rgb;
    let px = dpdx(input.position);
    let py = dpdy(input.position);
    let to_world_x = px / max(dot(px, px), 1e-8);
    let to_world_y = py / max(dot(py, py), 1e-8);
    let lum = luma(input.albedo.rgb);
    let lum_slope = dpdx(lum) * to_world_x + dpdy(lum) * to_world_y;
    let light_slope = dpdx(input.light.x) * to_world_x + dpdy(input.light.x) * to_world_y;
    let solid = input.fluid == 0u && !input.translucent;
    let foliage = select(0.0, 1.0, input.material == LEAVES || input.material == PLANTS || input.material == TALL_PLANTS
        || input.material == DOUBLE_LOW || input.material == DOUBLE_HIGH);

    // LabPBR maps, where a resource pack ships them: the normal map bends the light, the specular
    // map gives gloss, metals and glowing texels.
    var normal = input.normal;
    var ao = input.ao;
    var gloss = 0.0;
    var f0 = 0.04;
    var pbr_glow = 0.0;
    if labpbr && block_pbr_maps() && solid {
        let lod = block_texture_lod();
        var uv = input.uv;
        if foliage == 0.0 && input.albedo.a >= 0.999 {
            uv = parallax_uv(input, lod);
            if any(uv != input.uv) {
                texel_colour = relief_albedo(uv, dx_uv, dy_uv, lod);
                albedo = texel_colour * input.tint.rgb;
            }
        }
        let nm = block_normal_map_level(uv, lod);
        let spec = block_specular_map_level(uv, lod);
        let t = input.tangent.xyz;
        let b = cross(input.normal, t) * input.tangent.w;
        let xy = nm.rg * 2.0 - 1.0;
        let z = sqrt(max(1.0 - dot(xy, xy), 0.0));
        let bent = normalize(t * xy.x + b * xy.y + input.normal * z);
        normal = normalize(mix(input.normal, bent, 1.0 - smoothstep(24.0, 64.0, length(input.position))));
        ao *= nm.b;
        gloss = spec.r;
        f0 = clamp(spec.g, 0.02, 1.0);
        pbr_glow = select(spec.a, 0.0, spec.a >= 0.999);
    }

    // Vanilla materials, told apart by their sprites (horizon-shaders.toml): stone is rough with a
    // strong grain, wood warm with a soft sheen along it, metal glossy and tinted by its colour.
    // `soak` is how dark rain makes it, `wet_gloss` how glossy.
    var relief = 0.0;
    var soak = 0.6;
    var wet_gloss = 0.55;
    var metal = 0.0;
    if !(labpbr && block_pbr_maps()) && solid {
        if input.material == STONE {
            gloss = 0.12;
            relief = 1.0;
            soak = 0.75;
            wet_gloss = 0.5;
        } else if input.material == WOOD {
            gloss = 0.18;
            relief = 0.4;
            soak = 0.55;
            wet_gloss = 0.2;
            albedo *= vec3<f32>(1.03, 1.0, 0.97);
        } else if input.material == METAL {
            // Oxidised copper (greener than red) is matte; bare metal shines.
            let oxidised = smoothstep(0.0, 0.08, albedo.g - albedo.r);
            gloss = mix(0.7, 0.22, oxidised);
            f0 = mix(0.6, 0.04, oxidised);
            metal = 1.0 - oxidised;
            relief = 0.15;
            soak = 0.95;
            wet_gloss = 0.9;
        }
        // The texture's own light and dark read as relief close up, fading out where a texel is
        // smaller than a pixel.
        if relief > 0.0 {
            let along = lum_slope - normal * dot(lum_slope, normal);
            let near = 1.0 - smoothstep(8.0, 24.0, length(input.position));
            normal = normalize(normal - along * 0.12 * relief * near);
        }
    }

    // Rain: the ground darkens and turns glossy, and water gathers in the hollows of what faces
    // the sky. Snow in the cold: what faces the sky whitens.
    if solid && input.material == GLASS { gloss = max(gloss, 0.94); }
    var wet = 0.0;
    var puddle = 0.0;
    if overworld() && solid {
        let exposed = smoothstep(0.78, 0.96, input.light.y);
        let up = smoothstep(0.7, 0.98, input.normal.y);
        wet = world_wetness() * exposed * min(rain_effects, 1.0);
        if wet > 0.001 {
            let hollows = fbm2(world.xz * 0.17);
            let fill = 0.25 * wet * min(rain_effects, 1.5);
            puddle = smoothstep(0.66 - fill, 0.71 - fill, hollows) * up * smoothstep(0.25, 0.6, wet) * (1.0 - foliage);
            albedo *= mix(1.0, soak, wet * (1.0 - 0.5 * foliage));
            albedo *= mix(1.0, 0.7, puddle);
            gloss = max(gloss, mix(wet_gloss * wet * (1.0 - foliage), 0.98, puddle));
            f0 = max(f0, 0.02);
        }
        let snow = block_snow(input.tint.rgb) * exposed * smoothstep(0.55, 0.9, input.normal.y);
        if snow > 0.001 {
            let drift = smoothstep(0.25, 0.55, noise2(world.xz * 1.7) * 0.45 + snow * 0.75);
            albedo = mix(albedo, rgb(0.93, 0.95, 1.0), snow * drift);
        }
    }

    let plant = input.material == PLANTS || input.material == TALL_PLANTS || input.material == DOUBLE_LOW || input.material == DOUBLE_HIGH;
    if plant {
        normal = normalize(normal + vec3<f32>(0.0, 1.2, 0.0));
        var h = fract(world.y);
        if input.material == DOUBLE_LOW { h = h * 0.5; }
        if input.material == DOUBLE_HIGH { h = 0.5 + 0.5 * h; }
        albedo *= mix(0.55, 1.0, smoothstep(0.0, 0.9, h));
    }

    var colour: vec3<f32>;
    if overworld() {
        // The sun's shadow, looked up once for the light and the glossy highlight below.
        var sun_shadow = vec3<f32>(1.0);
        if sun_open(input.position, input.light.y) > 0.0 {
            sun_shadow = shadow_at(input.position, normal, max(dot(normal, frame.light_direction), 0.0));
            if shadows && ray_ready() && solid && foliage == 0.0 && dot(input.normal, frame.light_direction) > 0.05
                && length(input.position) < min(frame.ray_distance, 40.0) && max(sun_shadow.r, max(sun_shadow.g, sun_shadow.b)) > 0.03 {
                if trace_any(input.position + input.normal * 0.045, frame.light_direction, 1.1) {
                    sun_shadow *= mix(0.35, 1.0, smoothstep(30.0, 40.0, length(input.position)));
                }
            }
        }
        colour = light_surface_shadowed(albedo, normal, input.position, input.light, ao, input.emission, input.colored_light, foliage, sun_shadow);
        // A touch of the game's directional shade keeps the faces of a block apart in the shade.
        colour *= mix(1.0, input.shade, 0.35);
        // Gloss: wet ground and puddles mirror the sky, gloss LabPBR surfaces catch the sun.
        if gloss > 0.05 {
            let view = normalize(input.position);
            var n = normal;
            if puddle > 0.01 {
                let drops = rain_rings(world.xz) * clamp(rain_effects, 0.0, 2.0);
                n = normalize(mix(normal, normalize(vec3<f32>(-drops.x, 1.0, -drops.y)), puddle));
            }
            let r = reflect(view, n);
            let cos_v = max(dot(-view, n), 0.0);
            let fresnel = (f0 + (1.0 - f0) * pow(1.0 - cos_v, 5.0)) * gloss * gloss;
            let open = sun_open(input.position, input.light.y);
            let lit_by = direct_light() * sun_shadow * open * cloud_shadow(input.position);
            // A metal mirrors in its own colour.
            let mirror_tint = mix(vec3<f32>(1.0), albedo / max(luma(albedo), 0.05), metal);
            var reflected = mirrored_sky(r) * smoothstep(0.4, 0.95, input.light.y);
            if gloss > 0.56 && fresnel > 0.012 && ray_ready() {
                reflected = ray_mirror(input.position, input.normal, r, reflected);
            }
            colour = mix(colour, reflected * mirror_tint, fresnel)
                // The highlight follows the face more than the texture's own relief, or a stone wall
                // under a grazing sun sparkles along every crack.
                + sun_specular(normalize(mix(input.normal, n, 0.3)), view, gloss, f0, lit_by) * mirror_tint;
            // Torchlight catches glossy surfaces too, from the side the light comes from (where
            // the block light grows across the surface).
            if input.light.x > 0.05 {
                let toward_light = normalize(light_slope * 3.0 + input.normal * 1.2);
                let torch = torch_light(input.position, input.light.x);
                let h = normalize(toward_light - view);
                // Off the face, not the texture's own relief: a highlight that follows every texel
                // edge breaks into speckles round a torch.
                let face_n = normalize(mix(input.normal, n, 0.25));
                let lobe = pow(max(dot(face_n, h), 0.0), mix(6.0, 40.0, gloss)) * (f0 + 0.15 * gloss) * gloss;
                colour += torch * lobe * mirror_tint * 0.8;
            }
        }
    } else {
        colour = light_elsewhere(albedo, input.lightmap, input.shade * ao, input.emission, input.colored_light);
    }

    // Light blocks glow from their brightest texels (flames, glowstone, lava), ores sparkle where
    // their coloured flecks are, and LabPBR emission lights its own texels.
    if block_glow > 0.0 {
        let texel = texel_colour;
        let bright = luma(texel);
        var glow = input.emission * pow(bright, 1.6) * 2.4;
        if input.material == ORES {
            let chroma = max(max(texel.r, texel.g), texel.b) - min(min(texel.r, texel.g), texel.b);
            glow += smoothstep(0.1, 0.3, chroma) * 0.35;
        }
        glow += pbr_glow * 1.5;
        // Lava is bright enough already: a lake of it would wash out.
        colour += albedo * glow * block_glow * select(0.6, 1.0, overworld()) * select(1.0, 0.35, input.fluid == 2u);
    }

    // The face's own normal, for the contact shade (post/ssao.wgsl): one found from the depth
    // alone wobbles on ground seen at a slant and darkens it in stripes.
    if solid {
        // Smoothness 0..1, plus 2 on bare metal (post/composite.wgsl reads both for its reflections).
        set_surface(input.normal, gloss + select(0.0, 2.0, metal > 0.5), pack_surface_data(luma(albedo), input.light.y));
    }

    var out = vec4<f32>(colour, input.albedo.a);
    if input.fluid == 1u && overworld() {
        out = water(input, colour);
    } else if input.translucent && input.material == GLASS && (mirror_water() || ray_ready()) {
        let eye_ray = normalize(input.position - eye_offset());
        let r = reflect(eye_ray, input.normal);
        let f = 0.04 + 0.96 * pow(1.0 - clamp(dot(-eye_ray, input.normal), 0.0, 1.0), 5.0);
        let env = mirrored_sky(r) * smoothstep(0.35, 0.95, input.light.y);
        let mirror = transparent_mirror(input, input.normal, r, env);
        let alpha = out.a * (1.0 - f) + f;
        out = vec4<f32>((out.rgb * out.a * (1.0 - f) + mirror * f) / max(alpha, 0.001), alpha);
    }
    return Surface(vec4<f32>(apply_fog(out.rgb, input.position), out.a));
}
