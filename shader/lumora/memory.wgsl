// The stages that read the sky's memory (sky_memory.wgsl) load it into the weather accessors of
// common.wgsl at the start of their work, so every effect follows the smoothed, local weather.
fn load_weather() {
    if sky_memory[7] > 0.5 {
        wx_loaded = true;
        wx_now = vec4<f32>(sky_memory[1], sky_memory[2], sky_memory[3], sky_memory[4]);
        wx_biome = vec3<f32>(sky_memory[5], sky_memory[6], sky_memory[0]);
    }
}
