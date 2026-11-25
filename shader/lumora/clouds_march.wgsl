// The clouds' march, shared by the cloud passes and the sky map the water mirrors
// (sky_map.wgsl): the cumulus layer (CLOUD_BASE..CLOUD_TOP in common.wgsl) and a high veil.

fn phase_hg(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.0001), 1.5);
}

// The clouds along the view ray `d`: rgb the light they send toward the eye, a how much of the
// sky behind them still shows. Ray marched through the cloud layer, each step lit by a short march
// toward the sun (the moon by night): bright tops, grey bottoms, silver edges round the sun, gold
// and rose at sunset, dark in a storm.
fn cloud_layer(d: vec3<f32>, jitter: f32, lit_too: bool) -> vec4<f32> {
    if cloud_cover() <= 0.01 || abs(d.y) < 0.004 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let cam = frame.camera_position;
    let ta = (CLOUD_BASE - cam.y) / d.y;
    let tb = (CLOUD_TOP - cam.y) / d.y;
    let t0 = max(min(ta, tb), 0.0);
    var t1 = max(ta, tb);
    if t1 <= 0.0 || t0 > 12000.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    t1 = min(t1, t0 + 1600.0);
    var counts = array<i32, 4>(14, 24, 36, 56);
    var light_counts = array<i32, 4>(1, 2, 3, 5);
    let steps = max(i32(f32(counts[min(quality, 3u)]) * cloud_step_scale), 8);
    let light_steps = light_counts[min(quality, 3u)];
    let dt = (t1 - t0) / f32(steps);
    let l = frame.light_direction;
    let cos_theta = dot(d, l);
    // Forward scattering for the silver lining, a little back scattering for the far side.
    let phase = phase_hg(cos_theta, 0.6) * 0.65 + phase_hg(cos_theta, -0.25) * 0.35;
    // The moon lights the clouds only faintly: by night they stay quiet shapes.
    let sun = direct_light() * (1.0 - 0.65 * night_amount());
    // By night the clouds stay dark shapes against the stars, lit only a little by the moon.
    let dim = 1.0 - 0.7 * night_amount();
    let amb_top = (sky_ambient() * 1.25 + atmosphere(vec3<f32>(0.0, 1.0, 0.0)) * 0.25) * dim;
    let amb_bottom = sky_ambient() * 0.3 * dim;
    var transmittance = 1.0;
    var light = vec3<f32>(0.0);
    let flash = lightning_flash() * 1.5;
    let flash_seed = vec2<f32>(floor(frame.time / 1.7) * 17.3, 3.1);
    for (var i = 0; i < steps; i++) {
        let t = t0 + (f32(i) + jitter) * dt;
        let p = cam + d * t;
        // Empty air is skipped on the cheap: the column's shape first, the puffs only inside.
        let density = cloud_density(p, true);
        if density <= 0.002 {
            continue;
        }
        let step_t = exp(-density * 0.05 * dt);
        if !lit_too {
            transmittance *= step_t;
            if transmittance < 0.02 {
                break;
            }
            continue;
        }
        // How much cloud lies between this point and the sun.
        var depth = 0.0;
        for (var j = 1; j <= light_steps; j++) {
            depth += cloud_density_coarse(p + l * (f32(j) * 30.0));
        }
        let to_sun = exp(-depth * 30.0 * 0.075 * 4.0 / f32(light_steps + 1));
        // Thin edges glow less than the dense insides ("powder").
        let powder = 1.0 - exp(-density * 2.5);
        let h = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
        var lit = sun * to_sun * phase * mix(0.6, 1.0, powder) + mix(amb_bottom, amb_top, h);
        // A lightning flash glows inside the storm clouds, brightest in one part of the sky.
        if flash > 0.0 {
            lit += rgb(0.8, 0.85, 1.0) * flash * (0.4 + 2.6 * pow(noise2(p.xz * 0.004 + flash_seed), 2.0)) * powder;
        }
        light += transmittance * (1.0 - step_t) * lit;
        transmittance *= step_t;
        if transmittance < 0.02 {
            break;
        }
    }
    // Far clouds sink into the haze of the horizon.
    let fade = exp(-t0 * 0.00022) * smoothstep(0.0, 0.06, abs(d.y));
    let haze = atmosphere(d) * (1.0 - transmittance);
    // They stay as opaque as they are: only their colour fades.
    return vec4<f32>(mix(haze, light, fade), transmittance);
}

// ---- The high veil ------------------------------------------------------------------------------
// A second, thin layer far above the cumulus: wisps of cirrus on fair days, a sheet that thickens
// ahead of the rain, and torn streaks after it. Flat (one sample, no march), lit through: white by
// day, gold and rose at sunrise and sunset.

// Far above the cumulus (CLOUD_BASE..CLOUD_TOP): high enough that its wisps read as small, fine
// and distant, and drift slower than the clouds below.
const HIGH_CLOUD: f32 = 1900.0;

// How much of the sky the high veil may cover now.
fn high_cover() -> f32 {
    let fair = 0.12 * clouds;
    return clamp(fair + 0.75 * rain_arriving() + 0.3 * after_rain() + 0.4 * wx_overcast(), 0.0, 1.0);
}

// The veil along the view ray `d`: rgb its light, a how much of what lies above still shows.
fn high_layer(d: vec3<f32>) -> vec4<f32> {
    let cover = high_cover();
    if cover <= 0.01 || d.y < 0.01 || !overworld() {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let cam = frame.camera_position;
    let t = (HIGH_CLOUD - cam.y) / d.y;
    if t <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let p = (cam + d * t).xz + cloud_wind().xz * 0.7;
    // Long streaks along the wind: stretched one way, fine the other.
    let q = vec2<f32>(p.x * 0.0021, p.y * 0.0075);
    let streaks = fbm2(q + vec2<f32>(fbm2(q * 0.6) * 1.8, 0.0));
    let sheet = fbm2(p * 0.0011 + vec2<f32>(7.1, 3.3));
    let shape = mix(streaks, sheet, 0.35 + 0.4 * rain_arriving());
    let thick = smoothstep(0.66 - cover * 0.4, 0.76 - cover * 0.3, shape) * mix(0.3, 0.85, cover);
    if thick <= 0.002 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // Lit through by the sun (forward scattering), and by the sky.
    let cos_theta = dot(d, frame.light_direction);
    let phase = phase_hg(cos_theta, 0.5) * 0.7 + 0.3;
    // By night the veil is only a faint shape against the stars.
    let lit = (direct_light() * phase * 0.32 + sky_ambient() * 0.9) * (1.0 - 0.85 * night_amount());
    // Far off, the veil fades into the haze of the horizon.
    let fade = smoothstep(0.01, 0.12, d.y);
    let opacity = thick * fade;
    return vec4<f32>(lit * opacity, 1.0 - opacity);
}

// Both layers along `d`: the cumulus in front of the high veil.
// The share of the full step count a march takes (the temporal cloud pass sets it lower).
var<private> cloud_step_scale: f32 = 1.0;

fn clouds_all(d: vec3<f32>, jitter: f32, lit_too: bool) -> vec4<f32> {
    let low = cloud_layer(d, jitter, lit_too);
    if low.a < 0.02 {
        return low;
    }
    let high = high_layer(d);
    return vec4<f32>(low.rgb + low.a * high.rgb, low.a * high.a);
}
