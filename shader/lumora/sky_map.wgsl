// The sky the water mirrors, once a frame before the world draws: for every direction of the upper
// half of the sky, the air (atmosphere) with both cloud layers in front of it, so a lake mirrors
// the same clouds the camera sees. Stored by azimuth (x) and the square root of the height above
// the horizon (y), which gives the low sky, where reflections look, most of the rows.

fn sky_map_direction(cell: vec2<f32>, size: vec2<f32>) -> vec3<f32> {
    let uv = (cell + 0.5) / size;
    let azimuth = uv.x * 6.2831853;
    let up = uv.y * uv.y;
    let flat = sqrt(max(1.0 - up * up, 0.0));
    return vec3<f32>(cos(azimuth) * flat, up, sin(azimuth) * flat);
}

fn compute(input: ComputeInput) {
    load_weather();
    if !input.in_bounds {
        return;
    }
    let size = vec2<f32>(input.size.xy);
    let d = sky_map_direction(vec2<f32>(input.cell.xy), size);
    var c = atmosphere(d);
    if overworld() && cloud_cover() > 0.01 {
        let cl = clouds_all(d, 0.5, true);
        c = c * cl.a + cl.rgb;
    }
    textureStore(reflected_sky, vec2<i32>(input.cell.xy), vec4<f32>(c, 1.0));
}
