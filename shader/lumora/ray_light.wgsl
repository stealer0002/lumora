// The same incident light for specular hits and diffuse paths. All ray origins
// are camera-relative; a missing acceleration structure uses the raster passes.
fn ray_ready() -> bool {
    return ray_mode > 0u && frame.has_ray_tracing != 0u && frame.ray_distance > 1.0;
}

fn hit_radiance(hit: RayHit) -> vec3<f32> {
    let albedo = hit.albedo.rgb * hit.tint.rgb;
    let block = pow(hit.light.x, 2.4) * rgb(1.0, 0.76, 0.51);
    var irradiance = block + sky_ambient() * (0.28 * hit.light.y * hit.light.y);
    let ndl = max(dot(hit.normal, frame.light_direction), 0.0);
    if overworld() && ndl > 0.0 && hit.light.y > 0.03 {
        var sun = direct_light() * ndl * hit.light.y * cloud_shadow(hit.position);
        if shadows && trace_any(hit.position + hit.normal * 0.035, frame.light_direction, min(56.0, frame.ray_distance)) {
            sun = vec3<f32>(0.0);
        }
        irradiance += sun;
    }
    return albedo * (irradiance + vec3<f32>(hit.emission * 2.5));
}

fn ray_mirror(p: vec3<f32>, n: vec3<f32>, r: vec3<f32>, fallback: vec3<f32>) -> vec3<f32> {
    let reach = min(80.0, frame.ray_distance);
    if !ray_ready() || length(p) > reach || dot(r, n) < 0.005 { return fallback; }
    let hit = trace_layers(p + n * 0.045, r, reach, RAY_SOLID | RAY_ENTITY);
    if hit.distance < 0.0 { return fallback; }
    let fade = smoothstep(reach * 0.72, reach, max(length(p), hit.distance));
    return mix(apply_fog(hit_radiance(hit), hit.position), fallback, fade);
}
