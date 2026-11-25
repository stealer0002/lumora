// Mobs, players and block entities (chests, banners): the same light as the terrain.

fn entity(input: EntityInput) -> Surface {
    let base = input.albedo.rgb * input.tint.rgb;
    // The hurt, TNT and creeper flash, laid over in gamma as vanilla does.
    let g = vec3<f32>(1.0 / 2.2);
    let flashed = pow(mix(pow(base, g), pow(input.overlay.rgb, g), input.overlay.a), vec3<f32>(2.2));
    var colour: vec3<f32>;
    if overworld() {
        colour = light_surface(flashed, input.normal, input.position, input.light, 1.0, 0.0, input.colored_light, 0.0);
        colour *= mix(1.0, input.shade, 0.4);
        // Spider and enderman eyes, the warden's glow: as bright as the game makes them.
        if input.full_light {
            colour = max(colour, flashed * input.lightmap * input.shade);
        }
    } else {
        colour = light_elsewhere(flashed, input.lightmap, input.shade, 0.0, input.colored_light);
    }
    return Surface(vec4<f32>(apply_fog(colour, input.position), input.albedo.a * input.tint.a));
}
