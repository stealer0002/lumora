// One cosine-weighted path per half-resolution pixel per frame. Each of its
// two surface hits samples the direct light and can contribute emission.
fn diffuse_direction(n: vec3<f32>, xi: vec2<f32>) -> vec3<f32> {
    let axis = select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), abs(n.y) > 0.9);
    let t = normalize(cross(axis, n));
    let phi = 2.0 * PI * xi.x;
    let r = sqrt(xi.y);
    return t * (cos(phi) * r) + cross(n, t) * (sin(phi) * r) + n * sqrt(1.0 - xi.y);
}

fn path_gather(input: PostInput, point: vec3<f32>, normal: vec3<f32>) -> vec4<f32> {
    let phase = f32(frame.frame_index % 128u);
    let seed = vec2<f32>(hash12(floor(input.pixel) + 3.7), hash12(floor(input.pixel) + 42.1));
    var p = point;
    var n = normal;
    var energy = vec3<f32>(1.0);
    var light = vec3<f32>(0.0);
    var last_sky = 0.0;
    for (var bounce = 0; bounce < 2; bounce++) {
        let seq = seed + phase * vec2<f32>(0.7548777, 0.5698403);
        let xi = fract(select(seq, seq.yx * vec2<f32>(1.37, 1.71) + vec2<f32>(0.41, 0.83), bounce == 1));
        let d = diffuse_direction(n, xi);
        let hit = trace(p + n * 0.035, d, min(32.0, frame.ray_distance));
        if hit.distance < 0.0 {
            // The primary sky light is already in the material. Count only sky
            // carried to the receiver by a secondary surface.
            if bounce > 0 && overworld() {
                light += energy * sky_ambient() * (last_sky * last_sky);
            }
            break;
        }
        light += energy * hit_radiance(hit);
        energy *= clamp(hit.albedo.rgb * hit.tint.rgb, vec3<f32>(0.0), vec3<f32>(0.95));
        if max(energy.r, max(energy.g, energy.b)) < 0.012 { break; }
        p = hit.position;
        n = hit.normal;
        last_sky = hit.light.y;
    }
    // One path may strike a torch by chance: keep a single sample from flaring into a speck.
    light = min(light, vec3<f32>(1.2));
    let view_depth = (frame.projection * frame.view * vec4<f32>(point, 1.0)).w;
    let clip = frame.previous_view_projection * vec4<f32>(point + frame.camera_motion, 1.0);
    if clip.w > 0.05 && frame.delta_time > 0.0 && frame.delta_time < 0.125
        && length(frame.camera_motion) < 5.0 && lightning_flash() < 0.001 {
        let uv = clip.xy / clip.w * vec2<f32>(0.5, -0.5) + 0.5;
        if all(uv >= vec2<f32>(0.0)) && all(uv < vec2<f32>(1.0)) {
            let dims = vec2<f32>(textureDimensions(bounce_target_previous));
            let old = textureLoad(bounce_target_previous, vec2<i32>(uv * dims), 0);
            if old.a > 0.0 && abs(old.a - clip.w) < 0.045 + clip.w * 0.009 {
                light = mix(light, old.rgb, 0.92);
            }
        }
    }
    return vec4<f32>(light, view_depth);
}
