// Lumora: what every stage shares. The sky's colours, the sun's and the moon's light and the
// air's haze are all made here, so the fog on far terrain is the sky behind it.
// Every colour is linear light (shader API 0.2): 1.0 is the game's white.

override sun_strength: f32 = 2.0;
override saturation: f32 = 1.05;
override exposure: f32 = 1.0;
override fog_density: f32 = 1.0;
override fireflies: f32 = 1.0;
override star_brightness: f32 = 0.8;
override glow: f32 = 0.35;
override waving: bool = true;
override god_rays: f32 = 0.6;
override smooth_edges: bool = true;
override water_reflections: bool = true;
override clouds: f32 = 1.0;
// The quality preset, 0 Low, 1 Medium, 2 High, 3 Ultra, 4 Max: how many steps and samples every
// effect takes, and which effects run at all (below). Each effect's own option still applies: the
// preset only switches off what its level can't afford.
//   Low     a weak PC: crisp shadows, clouds, glow and the water mirror; nothing else costly.
//   Medium  + contact shade (Classic), sunbeams, light ripples, motion blur, screen mirrors on water.
//   High    + screen reflections on the ground and metal, lens flare, focus and background blur, parallax.
//   Ultra   + the most steps and samples, Accurate contact shade (when chosen).
//   Max     photorealism: + soft shadow edges, bounce light, Accurate contact shade always.
override quality: u32 = 2u;

// The Max preset: the pack's limit, where the costly extras switch on.
fn max_quality() -> bool {
    return quality >= 4u;
}
// Contact shade (post/ssao.wgsl), from Medium; Accurate (GTAO) from Ultra when chosen, always on Max.
fn ao_enabled() -> bool {
    return quality >= 1u && ambient_occlusion > 0.0;
}
fn ao_accurate() -> bool {
    return quality >= 4u || (quality >= 3u && ao_method == 1u);
}
// Screen-space mirrors: on water and glass from Medium, on the ground and metal from High.
fn mirror_water() -> bool {
    return screen_reflections && quality >= 1u;
}
fn mirror_terrain() -> bool {
    return screen_reflections && quality >= 2u;
}
// Sunbeams, light ripples and motion blur from Medium; the lens (flare, focus and background
// blur) and parallax from High.
fn shafts_enabled() -> bool {
    return god_rays > 0.0 && quality >= 1u;
}
fn caustics_amount() -> f32 {
    return select(0.0, clamp(caustics, 0.0, 2.0), quality >= 1u);
}
fn motion_enabled() -> bool {
    return motion_blur > 0.0 && quality >= 1u;
}
fn lens_enabled() -> bool {
    return quality >= 2u;
}
// Read by the game for the shadow map (`[shadow]`): whether it is drawn, its size and its reach.
override shadows: bool = true;
override shadow_resolution: u32 = 1u;
override shadow_distance: u32 = 1u;
// Rain and snow on the world, water, the night sky, surfaces, depth.
override rain_effects: f32 = 1.0;
override snow_cover: f32 = 1.0;
override water_refraction: bool = true;
override caustics: f32 = 1.0;
override aurora: f32 = 1.0;
override shooting_stars: bool = true;
override rainbow: f32 = 1.0;
override lightning: f32 = 1.0;
override labpbr: bool = true;
override block_glow: f32 = 1.0;
override ambient_occlusion: f32 = 1.0;
// Shadow edges that widen away from what casts them (0: crisp, as before).
override soft_shadows: f32 = 1.0;
// The clouds march half their steps each frame and add up over the frames.
override temporal_clouds: bool = true;
// How strongly lit surfaces pass their colour on to the surfaces round them (Max quality only).
override bounce_light: f32 = 1.0;
// How clear water is: 2 crystal, 1 natural, 0 murky.
override water_clarity: f32 = 1.0;
// How much the far distance softens (post/dof.wgsl).
override background_blur: f32 = 0.35;

// The terrain's `set_surface` data (material.wgsl): the albedo's lightness (0..1) and the sky light
// (0..1, in 32 steps), packed in one float, for the post passes.
fn pack_surface_data(albedo_lightness: f32, sky: f32) -> f32 {
    return round(clamp(sky, 0.0, 1.0) * 31.0) * 2.0 + clamp(albedo_lightness, 0.0, 0.999);
}
fn surface_sky(data: f32) -> f32 {
    return floor(data * 0.5) / 31.0;
}
fn surface_albedo(data: f32) -> f32 {
    return data - floor(data * 0.5) * 2.0;
}
override motion_blur: f32 = 0.5;
override lens_flare: f32 = 0.35;
override chromatic_aberration: f32 = 0.15;
override screen_reflections: bool = true;
override ray_mode: u32 = 0u;
override ao_method: u32 = 0u;
override parallax: bool = true;
override geometry_relief: bool = false;
override depth_of_field: f32 = 0.0;
override other_skies: bool = true;

const PI: f32 = 3.14159265;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, frame.luminance);
}

// Colours chosen by eye on a display are written in gamma and decoded here.
fn rgb(r: f32, g: f32, b: f32) -> vec3<f32> {
    return pow(vec3<f32>(r, g, b), vec3<f32>(2.2));
}

// Where the eye really is, relative to `frame.camera_position`, in blocks. View bobbing, a camera
// shake and nausea move it a few hundredths of a block, which `frame.projection` holds: a ray from
// the camera position through a pixel's near-plane point (0.05 blocks away) would swing with every
// step. The eye is the point the projection sends to (0, 0, z, 0). Post passes take view rays from
// it: `normalize(view_position(uv, 1.0) - eye_offset())`.
fn eye_offset() -> vec3<f32> {
    let e = frame.projection_inverse * vec4<f32>(0.0, 0.0, 1.0, 0.0);
    if abs(e.w) < 0.000001 {
        return vec3<f32>(0.0);
    }
    return (frame.view_inverse * vec4<f32>(e.xyz / e.w, 0.0)).xyz;
}

fn overworld() -> bool {
    return frame.dimension == 0;
}

// 1 by day, 0 by night, eased across sunrise and sunset.
fn day_amount() -> f32 {
    return smoothstep(-0.10, 0.16, frame.sun_direction.y);
}

// 1 in the dark of night, 0 from the end of dusk on.
fn night_amount() -> f32 {
    return 1.0 - smoothstep(-0.22, -0.02, frame.sun_direction.y);
}

// 1 while the sun is on the horizon (sunrise, sunset), 0 once it is well up or down.
fn twilight_amount() -> f32 {
    return 1.0 - smoothstep(0.0, 0.32, abs(frame.sun_direction.y + 0.03));
}

// ---- Weather and biome, as felt where the camera is --------------------------------------------
// The game's rain is the whole world's; these say how much of it falls here (none in a desert or a
// savanna, snow instead of rain in the cold), smoothed over a few seconds by the sky's memory
// (sky_memory.wgsl) in the stages that load it (memory.wgsl), instant elsewhere.
var<private> wx_loaded: bool = false;
var<private> wx_now: vec4<f32> = vec4<f32>(0.0);
var<private> wx_biome: vec3<f32> = vec3<f32>(0.0);

// Rain or snow falling here: grey skies, haze, fewer gaps in the clouds.
fn wx_overcast() -> f32 {
    if wx_loaded { return wx_now.x; }
    return frame.rain * select(0.0, 1.0, frame.precipitation != 0u);
}
// A thunderstorm here.
fn wx_thunder() -> f32 {
    if wx_loaded { return wx_now.y; }
    return frame.thunder * select(0.0, 1.0, frame.precipitation != 0u);
}
// Rain (not snow) falling here: drops on the water, rain streaks of light.
fn wx_rain() -> f32 {
    if wx_loaded { return wx_now.z; }
    return frame.rain * select(0.0, 1.0, frame.precipitation == 1u);
}
// How wet the ground here is: the game's wetness, only where rain can fall.
fn wx_wetness() -> f32 {
    if wx_loaded { return frame.wetness * wx_now.w; }
    return frame.wetness * select(0.0, 1.0, frame.precipitation == 1u);
}
// The biome round the camera: its temperature (vanilla's, -0.7..2) and downfall (0..1).
fn biome_temperature() -> f32 {
    if wx_loaded { return wx_biome.x; }
    return frame.temperature;
}
fn biome_downfall() -> f32 {
    if wx_loaded { return wx_biome.y; }
    return frame.downfall;
}

// Biome families, 0..1, from the temperature and downfall (they overlap at the edges and fade):
// hot and dry (desert, savanna, badlands), humid (jungle, swamp, mangrove, mushroom fields),
// cold (taiga, snowy biomes, peaks); what's left is the temperate land (plains, forests, oceans).
fn biome_arid() -> f32 {
    return smoothstep(1.1, 1.7, biome_temperature()) * (1.0 - smoothstep(0.15, 0.45, biome_downfall()));
}
fn biome_humid() -> f32 {
    return smoothstep(0.82, 0.92, biome_downfall()) * smoothstep(0.55, 0.85, biome_temperature());
}
fn biome_cold() -> f32 {
    return 1.0 - smoothstep(0.05, 0.5, biome_temperature());
}

// Clear sky 1, overcast 0.
fn clear_amount() -> f32 {
    return 1.0 - 0.6 * wx_overcast() - 0.25 * wx_thunder();
}

// The weather's moments, from the frame's rain and the ground's wetness: rain arriving (falling on
// dry ground) and the clear spell after it (rain gone, the ground still wet).
fn rain_arriving() -> f32 {
    return wx_overcast() * (1.0 - clamp(wx_wetness(), 0.0, 1.0));
}
fn after_rain() -> f32 {
    return clamp(wx_wetness(), 0.0, 1.0) * (1.0 - wx_overcast());
}

// ---- Hashes and noise -------------------------------------------------------------------------

fn hash13(p3_in: vec3<f32>) -> f32 {
    var p3 = fract(p3_in * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(hash13(i), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.0, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p_in: vec2<f32>) -> f32 {
    var p = p_in;
    var sum = 0.0;
    var amp = 0.5;
    for (var i = 0; i < 4; i++) {
        sum += amp * noise2(p);
        p = p * 2.03 + vec2<f32>(17.3, 9.1);
        amp *= 0.5;
    }
    return sum / 0.9375;
}

fn fbm3(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var sum = 0.0;
    var amp = 0.5;
    for (var i = 0; i < 4; i++) {
        sum += amp * noise3(p);
        p = p * 2.07 + vec3<f32>(13.1, 7.7, 3.3);
        amp *= 0.5;
    }
    return sum / 0.9375;
}

// ---- Storms ----------------------------------------------------------------------------------

// A lightning flash in a thunderstorm, 0..1: the sky lights up a few times a minute, each flash a
// quick double flicker. The game's own bolt is drawn by the game; this lights the clouds and the land.
fn lightning_flash() -> f32 {
    if wx_thunder() <= 0.05 || lightning <= 0.0 || !overworld() {
        return 0.0;
    }
    let slot = floor(frame.time / 1.7);
    let h = hash12(vec2<f32>(slot, 7.3));
    if h > 0.16 * wx_thunder() {
        return 0.0;
    }
    let local = fract(frame.time / 1.7) * 1.7;
    let first = exp(-max(local - 0.05, 0.0) * 18.0) * step(0.05, local);
    let second = exp(-max(local - 0.32, 0.0) * 9.0) * step(0.32, local) * 0.8;
    return clamp(first + second, 0.0, 1.0) * wx_thunder() * lightning;
}

// ---- Light ------------------------------------------------------------------------------------

// The sunlight reaching the ground: red and gold low down, nearly white high up.
fn sun_light() -> vec3<f32> {
    let h = frame.sun_direction.y;
    let low = rgb(1.0, 0.72, 0.48);
    // A warm, golden daylight.
    let high = rgb(1.0, 0.93, 0.83);
    var colour = mix(low, high, smoothstep(0.04, 0.5, h));
    // Each land its sun: a hot, dry glare over sand and savanna, a softer light through humid air.
    colour *= mix(vec3<f32>(1.0), vec3<f32>(1.05, 1.0, 0.92), biome_arid() * 0.7);
    colour *= 1.0 - 0.14 * biome_humid();
    return colour * sun_strength * smoothstep(-0.04, 0.12, h) * clear_amount();
}

// Moonlight: a cool, faint blue.
fn moon_light() -> vec3<f32> {
    let up = smoothstep(-0.04, 0.12, frame.moon_direction.y);
    return rgb(0.68, 0.77, 1.0) * 0.28 * up * clear_amount();
}

// The light of the body casting this frame's shadows (`frame.light_direction`).
fn direct_light() -> vec3<f32> {
    if !overworld() {
        return vec3<f32>(0.0);
    }
    let from_sun = dot(frame.light_direction, frame.sun_direction) > 0.5;
    return select(moon_light(), sun_light(), from_sun);
}

// The light of the whole sky on a surface facing up, at full sky light.
fn sky_ambient() -> vec3<f32> {
    let day = rgb(0.84, 0.89, 0.98) * 0.72;
    let dusk = rgb(0.86, 0.62, 0.62) * 0.36;
    // Enough at night to make out the land in the moonlight, soft and blue.
    // Under rain clouds the moon is gone, but the clouds still spread a faint glow (the moon's,
    // the far towns'): the land stays readable.
    let night = rgb(0.38, 0.45, 0.66) * (0.11 + 0.09 * wx_overcast());
    var c = mix(night, day, day_amount());
    c = mix(c, dusk, twilight_amount() * 0.5);
    // Overcast skies light evenly and greyer.
    c = mix(c, vec3<f32>(luma(c)) * 0.85, wx_overcast() * 0.6);
    // Storm clouds dim the day's light a lot; at night, under no moon, the land must still read:
    // the clouds take less of the faint night glow.
    let dim = 0.4 * wx_overcast() + 0.25 * wx_thunder();
    c = c * (1.0 - dim * mix(1.0, 0.4, night_amount()));
    // A lightning flash lights everything under the open sky, cold and blue.
    return c + rgb(0.75, 0.8, 1.0) * lightning_flash() * 1.6;
}

// ---- Water ------------------------------------------------------------------------------------

// The bright, wandering web of light that rippling water focuses onto what lies under it, at the
// world point `p`: about 1 on average, brighter along the lines, darker between them.
fn caustic_pattern(p: vec3<f32>) -> f32 {
    let t = frame.time * 0.55;
    let q = p.xz * 0.85 + vec2<f32>(p.y * 0.2);
    let a = noise3(vec3<f32>(q, t));
    let b = noise3(vec3<f32>(q * 1.7 + vec2<f32>(4.1, 2.3), t * 1.3 + 5.0));
    let ra = 1.0 - abs(a * 2.0 - 1.0);
    let rb = 1.0 - abs(b * 2.0 - 1.0);
    let lines = pow(ra, 6.0) * 0.9 + pow(rb, 8.0) * 0.7;
    return 0.55 + lines * 2.2;
}

// The colour light takes on in water per block it crosses (reds go first, then greens).
fn water_absorption() -> vec3<f32> {
    return vec3<f32>(0.42, 0.11, 0.075);
}

// ---- Rain and snow on the world --------------------------------------------------------------

// How wet the world is where rain falls: 0 dry, 1 soaked. Rises over half a minute of rain and
// dries afterwards (`wx_wetness()`). Not in the desert, the badlands or where it snows.
fn world_wetness() -> f32 {
    if !overworld() || rain_effects <= 0.0 {
        return 0.0;
    }
    let warm = smoothstep(0.1, 0.2, biome_temperature());
    let rains_here = smoothstep(0.0, 0.08, biome_downfall());
    return clamp(wx_wetness() * warm * rains_here, 0.0, 1.0);
}

// How much snow lies on what faces the sky in a cold biome: a frost that is always there, thick
// while it snows and after.
fn world_snow() -> f32 {
    if !overworld() || snow_cover <= 0.0 {
        return 0.0;
    }
    let cold = 1.0 - smoothstep(0.1, 0.2, biome_temperature());
    return cold * clamp((0.45 + 0.55 * wx_wetness()) * snow_cover, 0.0, 1.0);
}

// How cold the biome of one block is, from the colour the game tints its grass or leaves with
// (`tint`): the game only tells the shader the camera's biome, but the tint is each block's own,
// and the grass and leaves of snowy biomes are a cool blue-green that no warmer biome uses.
// 0 for a block the biome doesn't tint (stone, sand, wood): the game lays its own snow on those.
fn snowy_biome(tint: vec3<f32>) -> f32 {
    if max(abs(tint.r - 1.0), max(abs(tint.g - 1.0), abs(tint.b - 1.0))) < 0.03 {
        return 0.0;
    }
    let shown = pow(max(tint, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    return smoothstep(0.73, 0.77, shown.b / max(shown.g, 0.01));
}

// Snow on a block of tint `tint`: where its own biome is snowy, thicker while it snows.
fn block_snow(tint: vec3<f32>) -> f32 {
    if !overworld() || snow_cover <= 0.0 {
        return 0.0;
    }
    return snowy_biome(tint) * clamp((0.45 + 0.55 * wx_wetness()) * snow_cover, 0.0, 1.0);
}

// ---- The sky ----------------------------------------------------------------------------------

// The colour of the air along the unit direction `d`, without the sun's disc (the game draws it):
// blue overhead, pale at the horizon, gold and rose round a low sun, deep blue by night.
fn atmosphere(d: vec3<f32>) -> vec3<f32> {
    let s = frame.sun_direction;
    let up = clamp(d.y, -1.0, 1.0);
    let height = max(up, 0.0);
    let toward = max(dot(d, s), 0.0);
    let day = day_amount();
    let dusk = twilight_amount();
    let night = night_amount();

    // Day: a deep, clear blue overhead fading to a bright, pale horizon.
    let day_zenith = rgb(0.22, 0.47, 0.92);
    let day_horizon = rgb(0.70, 0.84, 1.0);
    let horizon_band = pow(1.0 - height, 4.0);
    var c = mix(day_zenith, day_horizon, horizon_band) * 1.05;

    // Sunrise and sunset: gold and orange along the horizon toward the sun, rose and violet above
    // it and on the far side.
    let side = pow(toward, 1.5);
    let dusk_horizon = mix(rgb(0.66, 0.56, 0.76), rgb(1.0, 0.66, 0.34), side);
    let dusk_high = mix(rgb(0.26, 0.33, 0.66), rgb(0.86, 0.62, 0.60), side * side);
    let dusk_sky = mix(dusk_high, dusk_horizon, pow(1.0 - height, 3.0));
    c = mix(c * day, dusk_sky * 0.9, dusk * (1.0 - 0.5 * day));

    // Night: navy overhead, a little lighter and greener near the horizon.
    let night_sky = mix(rgb(0.035, 0.05, 0.11), rgb(0.07, 0.10, 0.16), horizon_band);
    c = mix(c, night_sky, night);

    // The glow round the sun (forward scattering), stronger low down.
    let glow_sun = pow(toward, 12.0) * 0.6 + pow(toward, 3.0) * 0.18 * (0.4 + dusk);
    c += sun_light() / max(sun_strength, 0.01) * glow_sun * smoothstep(-0.2, 0.05, s.y);
    // A soft glow round the moon.
    let toward_moon = max(dot(d, frame.moon_direction), 0.0);
    c += rgb(0.55, 0.65, 0.95) * pow(toward_moon, 24.0) * 0.08 * night * clear_amount();

    // Below the horizon: the haze darkens toward the ground.
    if up < 0.0 {
        c *= mix(1.0, 0.45, smoothstep(0.0, 0.4, -up));
    }

    // Rain: grey, darker clouds over everything.
    let grey = vec3<f32>(luma(c)) * vec3<f32>(0.92, 0.95, 1.0);
    // At night the clouds are already dark: they dim it less.
    c = mix(c, grey * mix(0.7 - 0.35 * wx_thunder(), 0.9, night), wx_overcast() * 0.85);
    return c;
}

// A rainbow opposite the sun, along the unit direction `d`: a band 42 degrees round the point
// opposite the sun, red outside, violet inside, with a faint second bow outside it.
fn rainbow_light(d: vec3<f32>) -> vec3<f32> {
    let anti = -frame.sun_direction;
    let angle = acos(clamp(dot(d, anti), -1.0, 1.0));
    let x = (angle - 0.700) / 0.040;
    let x2 = (0.940 - angle) / 0.060;
    var c = vec3<f32>(0.0);
    if x > -0.2 && x < 1.2 {
        let w = smoothstep(-0.2, 0.15, x) * (1.0 - smoothstep(0.85, 1.2, x));
        c += hue(clamp(x, 0.0, 1.0)) * w;
    }
    if x2 > -0.2 && x2 < 1.2 {
        let w = smoothstep(-0.2, 0.15, x2) * (1.0 - smoothstep(0.85, 1.2, x2));
        c += hue(clamp(x2, 0.0, 1.0)) * w * 0.35;
    }
    return c * smoothstep(0.0, 0.12, d.y);
}

// Violet (0) to red (1).
fn hue(x: f32) -> vec3<f32> {
    let r = smoothstep(0.45, 0.85, x) + smoothstep(0.15, 0.0, x) * 0.35;
    let g = smoothstep(0.2, 0.45, x) * (1.0 - smoothstep(0.65, 0.9, x));
    let b = 1.0 - smoothstep(0.25, 0.5, x);
    return vec3<f32>(r, g, b);
}

// How much of a rainbow shows now: once the rain eases with the sun out, while the land is still
// wet, and with the sun low enough for the bow to stand above the horizon.
fn rainbow_amount() -> f32 {
    if !overworld() || rainbow <= 0.0 {
        return 0.0;
    }
    let after = wx_wetness() * (1.0 - smoothstep(0.2, 0.6, wx_overcast())) * day_amount();
    let low_sun = 1.0 - smoothstep(0.45, 0.7, frame.sun_direction.y);
    return after * low_sun * rainbow * (1.0 - wx_thunder());
}

// ---- Fog --------------------------------------------------------------------------------------

// What the air does to a surface at the camera-relative `position` whose lit colour is `colour`:
// a haze that thickens with distance and toward the valleys, a mist near the ground at night and
// at dawn, and the fade into the sky at the edge of the world. Under water, in lava, in the Nether
// and the End and under blindness, vanilla's own fog.
fn apply_fog(colour: vec3<f32>, position: vec3<f32>) -> vec3<f32> {
    let vanilla = vanilla_fog(position);
    // Under water: the pack's own murk, blue-green and lit by the sky above, thicker the deeper
    // the eye is under the open sky's light.
    if frame.eye_in == 1u && overworld() {
        let dist = length(position);
        let lit = sky_ambient() * (0.25 + 0.75 * frame.eye_light_smooth.y) + rgb(1.0, 0.74, 0.48) * frame.eye_light_smooth.x * 0.15;
        let murk = rgb(0.10, 0.36, 0.46) * lit * 0.9 + vec3<f32>(0.002, 0.006, 0.008);
        // Close by, the bed keeps its own colours, only cooled a little; the murk gathers past a
        // few blocks and hides what lies far off.
        let absorb = exp(-dist * vec3<f32>(0.10, 0.045, 0.035));
        let cloud = 1.0 - exp(-max(dist - 4.0, 0.0) * 0.065);
        let fogged = colour * absorb * (1.0 - cloud) + murk * cloud;
        return mix(fogged, murk, smoothstep(0.85, 1.0, vanilla));
    }
    let special = frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 || !overworld();
    if special {
        let g = vec3<f32>(1.0 / 2.2);
        return pow(mix(pow(max(colour, vec3<f32>(0.0)), g), pow(frame.fog_color, g), vanilla), vec3<f32>(2.2));
    }
    let dist = length(position);
    let dir = position / max(dist, 0.001);
    // The air's colour toward the surface: the sky just above the horizon that way.
    let toward = normalize(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.35 + 0.02, dir.z));
    let outdoors = smoothstep(0.2, 0.9, frame.eye_light_smooth.y);
    var air = atmosphere(toward);
    // At sunrise and sunset the sun's glow belongs to the far air: near the camera the air takes
    // the horizon's colour beside the sun, so the land in front of it keeps its shape.
    let twilight = twilight_amount();
    if twilight > 0.01 && overworld() {
        let sun_flat = normalize(vec3<f32>(frame.sun_direction.x, 0.0, frame.sun_direction.z) + vec3<f32>(0.0001, 0.0, 0.0));
        let sunward = pow(max(dot(normalize(vec3<f32>(dir.x, 0.0, dir.z) + vec3<f32>(0.0001, 0.0, 0.0)), sun_flat), 0.0), 3.0);
        if sunward > 0.01 {
            let beside = vec3<f32>(-sun_flat.z, toward.y, sun_flat.x);
            let calm_air = atmosphere(normalize(beside));
            air = mix(air, calm_air, sunward * twilight * (1.0 - smoothstep(48.0, 192.0, dist)));
        }
    }
    // In rain the air is no brighter than the light that reaches the land: a dim, wet air rather
    // than a pale veil.
    if wx_overcast() > 0.01 {
        let lit = air * clamp(luma(sky_ambient()) * 1.35 / max(luma(air), 0.001), 0.3, 1.0);
        air = mix(air, lit * vec3<f32>(0.96, 0.98, 1.02), wx_overcast());
    }
    // Each land its air: warm dust over deserts and savannas, a green, steamy haze over jungles
    // and swamps, thin, cool, clear air in the cold.
    let arid = biome_arid();
    let humid = biome_humid();
    let chill = biome_cold();
    air *= mix(vec3<f32>(1.0), vec3<f32>(1.12, 0.98, 0.8), arid * 0.55);
    air *= mix(vec3<f32>(1.0), vec3<f32>(0.9, 1.05, 0.93), humid * 0.55);
    air *= mix(vec3<f32>(1.0), vec3<f32>(0.94, 0.99, 1.07), chill * 0.45);
    air = mix(rgb(0.03, 0.035, 0.045), air, outdoors);

    // Haze: denser low down (sea level and the valleys), at night, at dawn and in rain.
    let world_y = position.y + frame.camera_position.y;
    let low = exp(-max(world_y - 63.0, 0.0) * 0.025);
    let thin = 0.35 + 0.65 * low;
    // The clear spell after rain: the air is cleaner than on an ordinary day.
    let washed = 1.0 - 0.4 * after_rain();
    let land = 1.0 + 0.7 * arid + 1.1 * humid - 0.35 * chill;
    let density = (0.0007 + 0.0016 * night_amount() + 0.0022 * twilight_amount()) * thin * fog_density * washed * land;
    // Rain thickens the air only past the first couple of dozen blocks, so the wet foreground stays
    // clear and the distance fades away; arriving rain thins it while the ground is still dry.
    let rain_density = 0.006 * wx_overcast() * mix(0.45, 1.0, clamp(wx_wetness(), 0.0, 1.0)) * thin * fog_density;
    var haze = 1.0 - exp(-(dist * density + max(dist - 24.0, 0.0) * rain_density));
    // Night and dawn mist hugging the ground, out of sight indoors.
    let mist = (0.6 * night_amount() + 0.25 * twilight_amount()) * fog_density * outdoors;
    let ground = exp(-max(world_y - 62.0, 0.0) * 0.12);
    haze = max(haze, (1.0 - exp(-dist * 0.012 * mist * ground)) * 0.85);
    let amount = max(haze * outdoors, vanilla);
    return mix(colour, air, clamp(amount, 0.0, 1.0));
}

// ---- Clouds -----------------------------------------------------------------------------------

// The cloud layer, in world heights: flat bottoms at the base, rounded tops below the top.
const CLOUD_BASE: f32 = 210.0;
const CLOUD_TOP: f32 = 310.0;

// How the clouds drift, in blocks.
fn cloud_wind() -> vec3<f32> {
    return vec3<f32>(frame.time * 3.2, 0.0, frame.time * 1.1);
}

// How much of the sky the clouds cover: the option's share on a fair day, nearly all in a storm.
fn cloud_cover() -> f32 {
    // Clear nights show the stars: fewer clouds after dark.
    let fair = 0.46 * clouds * mix(1.0, 0.42, night_amount()) * (1.0 - 0.55 * biome_arid()) * (1.0 + 0.35 * biome_humid());
    // Rain leaves a few gaps for the light to come through; only a storm closes the sky. After the
    // rain the clouds break up but linger.
    let ceiling = mix(0.8, 0.97, wx_thunder());
    return clamp(fair + 0.42 * wx_overcast() + 0.1 * wx_thunder() + 0.2 * after_rain(), 0.0, ceiling);
}

// The clouds' big shapes, seen from below: 0..1 at world column `xz`.
fn cloud_shape(xz: vec2<f32>) -> f32 {
    let p = xz + cloud_wind().xz;
    return noise2(p * 0.0034) * 0.5 + noise2(p * 0.0081 + vec2<f32>(5.2, 7.7)) * 0.32
        + noise2(p * 0.019 + vec2<f32>(1.7, 3.1)) * 0.18;
}

// The same shapes, coarse: for how much cloud lies toward the sun.
fn cloud_shape_coarse(xz: vec2<f32>) -> f32 {
    let p = xz + cloud_wind().xz;
    return noise2(p * 0.0034) * 0.6 + noise2(p * 0.0081 + vec2<f32>(5.2, 7.7)) * 0.4;
}

// How thick the cloud is at `p`, coarsely, for the light's march.
fn cloud_density_coarse(p: vec3<f32>) -> f32 {
    let h = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
    if h <= 0.0 || h >= 1.0 {
        return 0.0;
    }
    let lo = 0.66 - cloud_cover() * 0.42;
    let base = smoothstep(lo, lo + 0.2, cloud_shape_coarse(p.xz));
    let d = base - smoothstep(0.08, 1.0, h) * 0.6 - (1.0 - smoothstep(0.0, 0.07, h)) * 0.6;
    return clamp(d * 1.6, 0.0, 1.0);
}

// How thick the cloud is at world point `p`, 0..1; `detail` erodes its edges into puffs.
fn cloud_density(p: vec3<f32>, detail: bool) -> f32 {
    let h = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
    if h <= 0.0 || h >= 1.0 {
        return 0.0;
    }
    let cover = cloud_cover();
    let lo = 0.66 - cover * 0.42;
    let base = smoothstep(lo, lo + 0.2, cloud_shape(p.xz));
    // Flat bottoms, tops that narrow as they rise.
    var d = base - smoothstep(0.08, 1.0, h) * 0.6 - (1.0 - smoothstep(0.0, 0.07, h)) * 0.6;
    if d <= 0.0 {
        return 0.0;
    }
    if detail {
        let q = p + cloud_wind() * 1.7 + vec3<f32>(0.0, frame.time * 0.6, 0.0);
        let e = noise3(q * 0.045) * 0.6 + noise3(q * 0.11) * 0.4;
        d -= e * 0.55 * (1.0 - smoothstep(0.25, 0.95, d));
    }
    return clamp(d * 1.6, 0.0, 1.0);
}

// The shade the clouds cast at the camera-relative `position`: 1 in the open, less under a cloud.
fn cloud_shadow(position: vec3<f32>) -> f32 {
    if clouds <= 0.0 && wx_overcast() <= 0.0 {
        return 1.0;
    }
    let world = position + frame.camera_position;
    let l = frame.light_direction;
    let up = max(l.y, 0.12);
    let at = world + l * ((CLOUD_BASE + 25.0 - world.y) / up);
    let cover = cloud_cover();
    let lo = 0.66 - cover * 0.42;
    let shade = smoothstep(lo + 0.04, lo + 0.16, cloud_shape(at.xz));
    return 1.0 - shade * 0.8;
}
