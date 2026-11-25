// Integrate diffuse visibility between the two screen-space horizons of each
// slice. Angles are measured from the eye direction in the slice plane.
fn visible_arc(horizon: f32, tilt: f32) -> f32 {
    return 0.25 * (cos(tilt) - cos(2.0 * horizon - tilt) + 2.0 * horizon * sin(tilt));
}

fn ground_visibility(uv: vec2<f32>, p: vec3<f32>, n: vec3<f32>, depth: f32, pixel: vec2<f32>) -> f32 {
    let eye = normalize(eye_offset() - p);
    let dist = length(p - eye_offset());
    let radius = 1.35;
    let size = frame.resolution;
    let reach = clamp(radius * frame.projection[1][1] * size.y * 0.5 / max(dist, 0.15), 2.0, 110.0);
    let slices = 2 + i32(min(quality, 4u));
    let steps = 3 + i32(min(quality, 3u));
    let rotation = hash12(floor(pixel)) * PI / f32(slices);
    var visible = 0.0;
    var full = 0.0;
    for (var i = 0; i < slices; i++) {
        let phi = rotation + PI * f32(i) / f32(slices);
        let axis = vec2<f32>(cos(phi), sin(phi)) / size;
        let world_axis = view_position(uv + axis, depth) - p;
        let planar = world_axis - eye * dot(world_axis, eye);
        let tangent = planar / max(length(planar), 1e-7);
        let nv = max(0.0, dot(n, eye));
        let nt = dot(n, tangent);
        let norm = max(length(vec2<f32>(nt, nv)), 0.00001);
        let tilt = atan2(nt, max(nv, 0.00001));
        for (var side = 0; side < 2; side++) {
            let sign = select(-1.0, 1.0, side == 1);
            let angle = tilt * sign;
            let open_angle = 0.5 * PI + angle;
            var horizon_cos = cos(open_angle);
            for (var j = 1; j <= steps; j++) {
                let t = f32(j) / f32(steps);
                // On a texel's centre, so the depth read and the position rebuilt from it agree: off
                // centre, a slanted floor seems to rise and fall a little, in stripes.
                let suv = (floor((uv + sign * axis * max(1.0, reach * t * t)) * size) + 0.5) / size;
                if any(suv <= vec2<f32>(0.0)) || any(suv >= vec2<f32>(1.0)) { continue; }
                let z = depth_at(suv);
                if z <= 0.0 { continue; }
                let v = view_position(suv, z) - p;
                let len = length(v);
                // Rising clearly above the surface, by more the farther out (the depth's rounding).
                if len < 0.045 || dot(n, v) < 0.02 + len * (0.1 + dist * 0.0015) { continue; }
                let candidate = dot(eye, v) / len;
                let falloff = 1.0 - smoothstep(radius * 0.4, radius, len);
                horizon_cos = max(horizon_cos, mix(cos(open_angle), candidate, falloff));
            }
            let horizon = min(open_angle, acos(clamp(horizon_cos, -1.0, 1.0)));
            visible += norm * visible_arc(horizon, angle);
            full += norm * visible_arc(open_angle, angle);
        }
    }
    return clamp(visible / max(full, 0.001), 0.0, 1.0);
}
