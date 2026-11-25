// The Overworld's sky: the air from `atmosphere`, and by night stars that turn with the sky, twinkle
// and come in all colours, over a faint Milky Way. The game draws its sun and moon on top, and the
// pack's clouds come over all of it in the first post pass.

// The direction `d` in the sky's own frame: the stars turn with the sun, round the z axis.
fn celestial(d: vec3<f32>) -> vec3<f32> {
    let s = frame.sun_direction;
    let a = atan2(s.y, s.x);
    let c = cos(a);
    let n = sin(a);
    // Undo the sun's turn, then tilt the pole a little so the Milky Way doesn't sit on the path.
    let r = vec3<f32>(c * d.x + n * d.y, -n * d.x + c * d.y, d.z);
    let t = 0.4;
    return vec3<f32>(r.x, cos(t) * r.y - sin(t) * r.z, sin(t) * r.y + cos(t) * r.z);
}

// How wide one pixel of the screen is, as an angle.
fn pixel_angle() -> f32 {
    return 2.0 / (frame.projection[1][1] * frame.resolution.y);
}

// One layer of stars: cells of `scale` across, each holding a star with chance `chance`.
fn star_layer(p: vec3<f32>, scale: f32, chance: f32, size: f32) -> vec3<f32> {
    let q = p * scale;
    let cell = floor(q);
    let h = hash33(cell + 17.0);
    if h.x > chance {
        return vec3<f32>(0.0);
    }
    // The star sits somewhere in its cell, seen on the unit sphere.
    let star = normalize(cell + 0.25 + 0.5 * hash33(cell + 3.1));
    let off = length(normalize(p) - star);
    let radius = max(pixel_angle() * size, 0.0004);
    let core = exp(-off * off / (radius * radius));
    // Brightness: most are faint, a few are bright.
    let bright = pow(h.y, 6.0) * 2.6 + 0.07 + 0.18 * h.y;
    // Colour: blue-white to warm, as stars are.
    let tone = mix(rgb(0.70, 0.80, 1.0), rgb(1.0, 0.86, 0.66), h.z);
    // Twinkle, more near the horizon.
    let tw = 0.88 + 0.12 * sin(frame.time * (1.0 + 2.5 * h.z) + h.y * 40.0);
    return tone * core * bright * tw;
}

fn milky_way(p: vec3<f32>) -> vec3<f32> {
    let band_normal = normalize(vec3<f32>(0.3, 0.2, 0.93));
    let across = dot(p, band_normal);
    let band = exp(-across * across / 0.018);
    let clouds = fbm3(p * 5.0);
    let dust = smoothstep(0.42, 0.62, fbm3(p * 11.0 + 7.0));
    let light = band * (0.35 + 0.65 * clouds) * (1.0 - 0.7 * dust * band);
    let colour = mix(rgb(0.45, 0.42, 0.75), rgb(0.85, 0.72, 0.62), clouds);
    return colour * light * 0.022;
}

// A shooting star now and then on clear nights: each few seconds may bring one, a short bright
// streak with a fading tail, somewhere in the upper sky. Returns its light along `d`.
fn shooting_star(d: vec3<f32>) -> vec3<f32> {
    let period = 3.5;
    let slot = floor(frame.time / period);
    let h = hash33(vec3<f32>(slot, 5.1, 9.7));
    if h.x > 0.35 {
        return vec3<f32>(0.0);
    }
    let life = 0.9;
    let age = fract(frame.time / period) * period - h.y * (period - life);
    if age < 0.0 || age > life {
        return vec3<f32>(0.0);
    }
    let h2 = hash33(vec3<f32>(slot, 1.3, 4.4));
    // Where it starts (well above the horizon) and which way it falls (a little downward).
    let az = h2.x * 2.0 * PI;
    let el = 0.35 + 0.6 * h2.y;
    let start = vec3<f32>(cos(az) * cos(el), sin(el), sin(az) * cos(el));
    let side = normalize(cross(start, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(0.0, 0.0001, 0.0));
    let way = normalize(side * select(-1.0, 1.0, h2.z > 0.5) - vec3<f32>(0.0, 0.45, 0.0));
    let travel = 0.55 * age / life;
    let head = normalize(start + way * travel);
    let tail = normalize(start + way * max(travel - 0.16, 0.0));
    // Distance from `d` to the streak from tail to head.
    let ab = head - tail;
    let k = clamp(dot(d - tail, ab) / max(dot(ab, ab), 0.000001), 0.0, 1.0);
    let off = length(d - (tail + ab * k));
    let width = max(pixel_angle() * 0.9, 0.0006);
    let core = exp(-off * off / (width * width));
    let fade = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.6, 1.0, age / life));
    return rgb(0.85, 0.92, 1.0) * core * k * k * fade * 3.5;
}

// The northern lights: curtains of green fading to violet at their tops, rippling slowly across
// the northern sky on clear nights in cold places. Marched through a few layers of height.
fn aurora_light(d: vec3<f32>) -> vec3<f32> {
    if d.y < 0.08 {
        return vec3<f32>(0.0);
    }
    var counts = array<i32, 4>(8, 12, 18, 26);
    let steps = counts[min(quality, 3u)];
    let t = frame.time * 0.05;
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < steps; i++) {
        let f = f32(i) / f32(steps);
        // Tall curtains, high up: their foot well above the horizon, their tops far up the sky.
        let height = 1.0 + f * 2.2;
        let p = d.xz * (height / d.y) * 0.32;
        // Curtains: folded bands, warped so they bend and drift.
        let warp = vec2<f32>(noise2(p * 0.7 + vec2<f32>(t, 0.0)), noise2(p * 0.7 + vec2<f32>(3.3, t)));
        let q = p + warp * 1.6;
        let band = 1.0 - abs(noise2(vec2<f32>(q.x * 0.9 + t * 2.0, q.y * 0.35)) * 2.0 - 1.0);
        let curtain = pow(band, 10.0) * (0.6 + 0.4 * noise2(q * 4.0 + vec2<f32>(0.0, t * 8.0)));
        // Mostly toward the north (-z), and thinning as they rise.
        let north = smoothstep(0.2, -0.6, d.z / max(length(d.xz), 0.001));
        let colour = mix(rgb(0.25, 1.0, 0.55), rgb(0.62, 0.32, 1.0), smoothstep(0.25, 0.95, f));
        sum += colour * curtain * (1.0 - f) * north;
    }
    let fade = smoothstep(0.08, 0.32, d.y) * (1.0 - smoothstep(0.9, 1.0, d.y));
    return sum / f32(steps) * fade * 0.6;
}

// How much the northern lights show here and now: clear nights in cold biomes.
fn aurora_amount() -> f32 {
    // How cold it has been round the camera lately (sky_memory.wgsl), not this instant's biome.
    let cold = clamp(sky_memory[0], 0.0, 1.0);
    return night_amount() * cold * (1.0 - wx_overcast()) * aurora;
}

fn sky(input: SkyInput) -> vec4<f32> {
    load_weather();
    if !overworld() {
        return input.color;
    }
    let d = normalize(input.direction);
    var c = atmosphere(d);

    // One lead at a time. An aurora takes the whole sky; otherwise the moon, while it is up, with
    // the land's silhouette under it; and on moonless nights the Milky Way.
    var aur = vec3<f32>(0.0);
    var aur_amount = 0.0;
    if aurora > 0.0 {
        aur_amount = aurora_amount();
        if aur_amount > 0.001 {
            aur = aurora_light(d) * aur_amount;
        }
    }
    let moon_up = smoothstep(-0.02, 0.2, frame.moon_direction.y);
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    let under_aurora = (1.0 - 0.6 * aur_amount) / (1.0 + 10.0 * luma(aur));

    // The stars come out as the sky darkens, fade low in the haze, and hide behind rain.
    let dark = night_amount() * (1.0 - wx_overcast()) * star_brightness;
    if dark > 0.001 && d.y > -0.05 {
        let p = celestial(d);
        // Sparse and calm: a scatter of clear stars, not a spray of noise.
        var stars = star_layer(p, 140.0, 0.04, 0.9) + star_layer(p, 300.0, 0.01, 0.7) * 0.45;
        // More, fainter stars along the Milky Way.
        let band_normal = normalize(vec3<f32>(0.3, 0.2, 0.93));
        let across = dot(p, band_normal);
        stars += star_layer(p, 520.0, 0.07, 0.6) * exp(-across * across / 0.02) * 0.3;
        // The moon's light washes out the stars round it, and the Milky Way steps back.
        stars *= 1.0 - 0.75 * pow(toward_moon, 4.0) * moon_up;
        let band = milky_way(p) * mix(1.0, 0.45, moon_up);
        let haze = smoothstep(-0.05, 0.25, d.y);
        c += (stars * 0.9 + band) * dark * haze * under_aurora;
    }
    // A wider, soft glow round the moon: the brightest thing in a clear night sky.
    c += rgb(0.55, 0.64, 0.9) * pow(toward_moon, 6.0) * 0.035 * night_amount() * clear_amount() * moon_up * (1.0 - aur_amount);
    let clear_night = night_amount() * (1.0 - wx_overcast());
    if shooting_stars && clear_night > 0.3 && d.y > 0.0 {
        c += shooting_star(d) * clear_night * star_brightness;
    }
    c += aur;
    // A halo round the moon, 22 degrees out, on nights with a thin veil of high cloud.
    let to_moon = acos(clamp(dot(d, frame.moon_direction), -1.0, 1.0));
    let ring = exp(-pow((to_moon - 0.384) / 0.018, 2.0));
    let veil = 0.35 + 0.65 * smoothstep(0.3, 0.7, cloud_cover());
    c += rgb(0.72, 0.78, 0.95) * ring * 0.03 * night_amount() * veil * (1.0 - wx_overcast()) * smoothstep(-0.05, 0.1, frame.moon_direction.y);
    // A lightning flash lights the whole sky.
    c += rgb(0.7, 0.75, 1.0) * lightning_flash() * 0.6;
    // The clouds are drawn over this by the first post pass (post/clouds.wgsl), at half size.
    return vec4<f32>(c, 1.0);
}
