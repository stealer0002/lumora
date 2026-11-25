// Place the half-resolution path estimate on a full-resolution receiver. Use
// view-depth agreement so a foreground wall cannot borrow the room behind it.
fn path_upsample(uv: vec2<f32>, z: f32) -> vec3<f32> {
    // A 3x3 of half-size texels two apart (a 5-texel-wide footprint), Gaussian-weighted, each kept
    // only where its depth agrees with this pixel's: it averages the per-pixel noise of one path a
    // pixel away without letting light cross an edge.
    let dims = vec2<i32>(textureDimensions(bounce_target));
    let centre = vec2<i32>(uv * vec2<f32>(dims));
    var sum = vec3<f32>(0.0);
    var total = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let q = textureLoad(bounce_target, clamp(centre + vec2<i32>(x, y) * 2, vec2<i32>(0), dims - 1), 0);
            let spatial = select(0.6, 1.0, x == 0 && y == 0) * select(1.0, 0.6, x != 0 && y != 0);
            let w = spatial * (1.0 - smoothstep(0.035 + z * 0.005, 0.18 + z * 0.025, abs(q.a - z)));
            sum += q.rgb * w;
            total += w;
        }
    }
    return sum / max(total, 0.001);
}
