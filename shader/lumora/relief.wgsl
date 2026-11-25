// Both representations use the same LabPBR height scale, in blocks.
const RELIEF_DEPTH: f32 = 0.055;

// The unshifted sprite keeps the game's filter. For shifted UVs, whose explicit
// LOD has no gradient, integrate along the major axis of the texel footprint.
fn relief_albedo(uv: vec2<f32>, dx: vec2<f32>, dy: vec2<f32>, base_lod: f32) -> vec3<f32> {
    let dims = max(block_texture_size(), vec2<f32>(1.0));
    let a = dx * dims;
    let b = dy * dims;
    let xx = a.x * a.x + b.x * b.x;
    let yy = a.y * a.y + b.y * b.y;
    let xy = a.x * a.y + b.x * b.y;
    let disc = length(vec2<f32>(xx - yy, 2.0 * xy));
    let major2 = max((xx + yy + disc) * 0.5, 0.0);
    let major = sqrt(major2);
    let minor = sqrt(max((xx + yy - disc) * 0.5, 0.0));
    let cap = select(4.0, 8.0, quality >= 3u);
    let width = max(max(minor, major / cap), 1.0);
    let taps = i32(ceil(min(major / width, cap)));
    if taps < 2 { return block_texture_level(uv, base_lod).rgb; }
    var axis = vec2<f32>(xy, major2 - xx);
    if dot(axis, axis) < 1e-8 { axis = vec2<f32>(1.0, 0.0); }
    let step_uv = normalize(axis) * major / dims / f32(taps);
    let lod = log2(width);
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < taps; i++) {
        let q = uv + (f32(i) + 0.5 - 0.5 * f32(taps)) * step_uv;
        sum += block_texture_level(clamp(q, 0.5 / dims, 1.0 - 0.5 / dims), lod).rgb;
    }
    return sum / f32(taps);
}

fn displacement(input: DisplacementInput) -> f32 {
    return select(0.0, (1.0 - input.height) * RELIEF_DEPTH, labpbr);
}

// Intersect the view ray with the sprite heightfield, then interpolate the
// crossing between layers. Pin its edges like the displaced grid.
fn parallax_uv(input: MaterialInput, lod: f32) -> vec2<f32> {
    let amount = (1.0 - input.displaced) * (1.0 - smoothstep(22.0, 48.0, length(input.position)));
    if !parallax || !lens_enabled() || amount < 0.001 { return input.uv; }
    let eye = normalize(eye_offset() - input.position);
    let face = max(dot(eye, input.normal), 0.0);
    let tangent = input.tangent.xyz;
    let bitangent = cross(input.normal, tangent) * input.tangent.w;
    let edge = min(input.uv, 1.0 - input.uv);
    let pin = smoothstep(0.0, 0.065, min(edge.x, edge.y));
    let path = vec2<f32>(dot(eye, tangent), dot(eye, bitangent)) * RELIEF_DEPTH
        * (amount * pin / max(face, 0.22));
    if dot(path, path) < 1e-9 { return input.uv; }
    let half_texel = 0.5 / max(block_pbr_size(), vec2<f32>(1.0));
    let steps = i32(mix(7.0, 15.0 + 2.0 * f32(quality), 1.0 - face));
    let first = 1.0 - block_normal_map_level(input.uv, lod).a;
    if first < 0.001 { return input.uv; }
    var previous_gap = first;
    for (var i = 1; i <= steps; i++) {
        let t = f32(i) / f32(steps);
        let uv = clamp(input.uv - path * t, half_texel, 1.0 - half_texel);
        let gap = 1.0 - block_normal_map_level(uv, lod).a - t;
        if gap <= 0.0 {
            let f = previous_gap / max(previous_gap - gap, 0.0001);
            let hit = (f32(i - 1) + f) / f32(steps);
            return clamp(input.uv - path * hit, half_texel, 1.0 - half_texel);
        }
        previous_gap = gap;
    }
    return clamp(input.uv - path, half_texel, 1.0 - half_texel);
}
