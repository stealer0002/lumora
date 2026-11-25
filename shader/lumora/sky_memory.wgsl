// What the sky remembers from frame to frame, once a frame before the world draws (one invocation):
// the weather and the biome round the camera, each following the game's value over a few seconds
// instead of jumping at a biome's edge. So walking from the rain into a desert, the grey, the wet
// and the haze fade away; walking into the cold, the northern lights and the cold palette fade in.
//
// sky_memory: [0] cold 0..1, [1] overcast (rain or snow falling here) 0..1, [2] thunder here 0..1,
// [3] rain falling here (not snow) 0..1, [4] how wet the ground here may get 0..1, [5] the biome's
// temperature, [6] its downfall, [7] 1 once the memory holds values (a cleared buffer is zeros).

fn compute(input: ComputeInput) {
    if !input.in_bounds {
        return;
    }
    let falls = frame.precipitation != 0u;
    let rains = frame.precipitation == 1u;
    var goal = array<f32, 7>(
        1.0 - smoothstep(0.05, 0.5, frame.temperature),
        frame.rain * select(0.0, 1.0, falls),
        frame.thunder * select(0.0, 1.0, falls),
        frame.rain * select(0.0, 1.0, rains),
        select(0.0, 1.0, rains),
        frame.temperature,
        frame.downfall,
    );
    // The first frame after a load (or a clear) takes the values as they are: no fade from zero.
    let fresh = sky_memory[7] < 0.5;
    let step = select(1.0 - exp(-max(frame.delta_time, 0.0) / 5.0), 1.0, fresh);
    for (var i = 0; i < 7; i++) {
        sky_memory[i] = mix(sky_memory[i], goal[i], step);
    }
    sky_memory[7] = 1.0;
}
