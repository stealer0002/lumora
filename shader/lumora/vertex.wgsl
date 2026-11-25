// Wind (option `waving`): leaves, short plants, both halves of tall grass and the tall flowers sway,
// harder in gusts that sweep across the land and in storms; the water's surface heaves gently.
// The shadows move with them.

// How hard the wind blows at world point `world`: a steady breeze, gusts rolling across the land,
// and storms.
fn wind_at(world: vec3<f32>, t: f32) -> f32 {
    let breeze = 0.55 + 0.45 * sin(t * 0.21 + world.x * 0.02);
    let gust = smoothstep(0.45, 0.85, noise2(world.xz * 0.035 - vec2<f32>(t * 0.9, t * 0.35)));
    return (breeze + gust * 1.1) * (1.0 + frame.rain + frame.thunder);
}

// The sway of a plant's top at world column `world`, in blocks per unit of wind.
fn plant_sway(world: vec3<f32>, t: f32) -> vec3<f32> {
    return vec3<f32>(
        sin(t * 2.0 + world.x * 1.3 + world.z * 0.7) + 0.4 * sin(t * 4.7 + world.z * 2.1),
        0.0,
        sin(t * 1.6 + world.z * 1.1 + world.x * 0.5) + 0.4 * sin(t * 4.1 + world.x * 1.9),
    );
}

fn vertex(input: VertexInput) -> vec3<f32> {
    if !waving || !overworld() {
        return input.position;
    }
    let world = input.position + frame.camera_position;
    let t = frame.time;
    // Water: a slow swell, only ever lowering the surface so no seam opens at the banks.
    if input.fluid == 1u && fract(world.y + 0.001) > 0.5 {
        let swell = noise2(world.xz * 0.35 + vec2<f32>(t * 0.4, t * 0.25)) * 0.6 + noise2(world.xz * 0.9 - vec2<f32>(t * 0.6, -t * 0.3)) * 0.4;
        let storm = 1.0 + frame.rain + frame.thunder;
        return input.position - vec3<f32>(0.0, swell * 0.045 * storm, 0.0);
    }
    let wind = wind_at(world, t);
    if input.material == 10u {
        let o = vec3<f32>(
            sin(t * 1.7 + world.x * 0.9 + world.y * 0.5),
            sin(t * 2.3 + world.z * 0.8 + world.x * 0.3) * 0.5,
            sin(t * 1.5 + world.z * 0.9 + world.y * 0.4),
        );
        return input.position + o * 0.03 * wind;
    }
    // A short plant's top corners (the top of its sprite) move; its roots stay put.
    if input.material == 11u && input.uv.y < 0.5 {
        return input.position + plant_sway(world, t) * 0.07 * wind;
    }
    // Tall grass, large ferns and tall flowers: the lower half bends from the roots, the upper
    // half twice as far at its tip, so the two meet where they join.
    if input.material == 14u && input.uv.y < 0.5 {
        return input.position + plant_sway(world, t) * 0.06 * wind;
    }
    if input.material == 15u {
        let reach = select(0.06, 0.13, input.uv.y < 0.5);
        return input.position + plant_sway(world, t) * reach * wind;
    }
    return input.position;
}
