# Lumora

A shader pack for Horizon (shader API 0.2), written from scratch: a luminous Minecraft with one
foot in fantasy, easy on the eyes. Every scene is built the way a sunset is: a warm light coming
from one side, a cool lilac shade, and something left dark on purpose. The name blends *luminous*
and *aurora*.

## What it draws

- **Light:** sunlight (moonlight by night) through crisp shadow maps, coloured where it passes
  through stained glass or water; a sky light from above; block light in the colour of the lights
  round it (warm torches, blue soul fire that really paints the stone blue, red redstone).
  Canopies are lit on top and dark inside, a leaf glows where the sun is behind it, tufts of grass
  and flowers darken toward their roots, and the faces of a block stay apart.
- **Sky:** a sky of its own, blue overhead and pale at the horizon, gold and rose round a low sun,
  navy at night with twinkling stars of many colours and a Milky Way that turn with the sky.
- **Clouds:** volumetric cumulus clouds, lit by the sun or the moon, with grey bottoms and bright
  edges round the sun; thicker and darker in rain; their shadows drift over the land. Far above
  them, a thin high veil: wisps of cirrus on fair days, gold and rose at sunrise and sunset, a grey
  sheet thickening ahead of the rain and torn streaks after it.
- **Air:** haze that thickens with distance and toward the valleys, a ground mist at night and at
  dawn, light shafts through trees and haze, and far land fading into the sky. At sunrise and
  sunset the sun's glow stays in the far air, so the land in front of the sun keeps its shape.
- **Night:** one lead at a time. The northern lights over cold biomes take the whole sky (the
  stars step back under them); otherwise the moon and the land's silhouette while the moon is up,
  and the Milky Way on moonless nights. Fireflies are small points that blink near you and fade
  with distance; shooting stars now and then, and a halo round the moon.
- **Rain and storms:** four moments you can tell apart. Rain arriving: dark cloud bases over a
  still-bright horizon, thin air. Rain: a wet, legible foreground (dark, glossy ground, puddles
  mirroring the sky, drops ringing on water) and a distance that fades away, with the air no
  brighter than the light on the land. Storm: darker rather than denser, lit by lightning inside
  the clouds. After the rain: air clearer than on an ordinary day, broken clouds, wet ground and a
  rainbow opposite the sun.
- **Snow:** in cold biomes what faces the sky whitens, thicker while it snows.
- **Water:** see into the shallows: the bed bends with the ripples, shallow water stays
  turquoise and foamy even seen from the side, deep water goes dark blue-green, and a web of light
  (caustics) plays on what lies under it. Seen low, the water mirrors the land and the same sky the camera sees, clouds and all (a map
  of the sky made each frame before the world draws, 0.3 ms), broken
  up by a swell even far off, and keeps a little of its own colour; the sun's glint is one spot
  near by and a field of sparkles far off. Under water the bed keeps its colours close by and the
  murk hides the distance; looking up, the sky shows through a round window and the rest of the
  surface mirrors the water.
- **Surfaces:** stone is rough with its grain standing out close up, darkens a little in rain
  and turns glossy; wood is warm with a soft sheen and soaks dark in rain; metal shines in its own
  colour (oxidised copper is matte) and beads with water. Glossy surfaces catch torchlight from the
  side it comes from. Flames, glowstone, lamps and lava glow from their brightest texels, ores
  sparkle faintly, and LabPBR maps (from a resource pack that ships them) take over where present.
- **Picture:** soft contact shade in corners and under walls (ambient occlusion), a three-layer
  glow (bloom), a soft tone curve that keeps the shade readable and never burns to white, warm
  golden daylight, calm colour, cool shadows, a light vignette, optional depth of field and
  smooth edges (FXAA). The look is tuned to be easy on the eyes; raise Sun strength, Saturation,
  Glow and Light shafts for a stronger one.
- **Wind:** leaves, short plants and both halves of tall grass and tall flowers sway, harder in
  gusts that roll across the land and in storms, and their shadows with them.
- **Nether and End:** shimmering hot air in the Nether. In the End, the Rift: a tall, narrow tear
  low in one part of the violet sky, its ragged edges burning pale teal, slowly breathing, with
  threads of light drifting into it and the nebula leaning toward it; the stars are few and the
  bright ones gather near it.

## Presets

Pick one on the options page; every effect below it still has its own setting, and the preset only
switches off what its level can't afford.

| Preset | For | What it adds |
| --- | --- | --- |
| Low | weak PCs and laptops | crisp shadows, volumetric clouds, glow, the water mirror |
| Medium | average PCs | contact shade (Classic), light shafts, light ripples under water, motion blur, screen mirrors on water |
| High (default) | good PCs | screen reflections on the ground and metal, lens flare, focus and background blur, parallax |
| Ultra | strong PCs | the most steps and samples everywhere, Accurate contact shade (GTAO) when chosen |
| Max | photorealism | soft shadow edges that widen with distance, bounce light, Accurate contact shade always |

Shadow sharpness (2048 to 8192) and Shadow range are their own settings: on a weak PC, 2048 or
turning shadows off gains the most.

## Options

The options page opens on **Lumora** (the preset, the main switches and ray tracing) with a page
each for Lighting, Surfaces, Sky, Weather, Water and Picture.

- **Ray tracing:** Off, Reflections + shadows (traced reflections and contact shadows), or Full
  (adds two traced bounces of light at half size). Needs a GPU and Horizon backend with ray queries;
  without them the pack keeps its screen-space paths.
- **Picture:** colour, brightness, glow, motion blur (at 0.5 the shutter is 1/120 s), focus blur,
  background blur, lens flare, colour fringes and FXAA.
- **Surfaces:** wind, and the LabPBR features of a resource pack that ships them: parallax and 3D
  relief (geometry within 12 blocks, blending into parallax farther away).
- **Water:** clear water, its mirror, light ripples and how clear rivers and lakes are.

## Biomes and weather

Rain falls only where the biome lets it: deserts, savannas and badlands stay dry under a rainy
sky, cold biomes get snow, and walking from one into another fades the haze, the wet and the
clouds over a few seconds instead of jumping. Each land has its own air: warm dust over sand and
savanna, a green, steamy haze over jungles and swamps, thin cool air in the cold, and the
northern lights over snowy biomes at night. In the Nether each biome tints the picture with its
own fog.

## What's new in 1.3.0

- **Quality presets that mean something:** Low for weak PCs, Medium for average ones, High for good
  ones, Ultra for strong ones and Max for photorealism. Each level switches whole effects on or off
  (contact shade, sunbeams, reflections, lens effects, soft shadows, bounce light), not only their
  sample counts.
- **Ray tracing** (optional, needs ray queries): traced reflections and contact shadows, or full
  traced bounce light.
- **Biomes and weather:** rain only where the biome lets it fall (deserts, savannas and badlands stay
  dry), snow in the cold, smooth fades between biomes, each land with its own air, sunlight and
  colour; Nether biomes tint the picture with their own fog.
- **Soft shadow edges** on Max that widen with the distance to the caster; sharper shadows close by
  with the new 64-block shadow range.
- **Bounce light** on Max: lit surfaces pass their colour on to nearby walls.
- **Camera:** motion blur, background blur, a fuller lens flare.
- **Clouds:** fused, temporally smoothed volumetric clouds and a high veil far above them; clouds
  mirrored in water.
- **Water:** clearer rivers and lakes (Water clarity), steadier ripples, mirrored clouds.
- **Northern lights** follow how cold it has been round you, and sit higher in the sky.
- **Options page** rebuilt: a start page with the preset, then Lighting, Surfaces, Sky, Weather,
  Water and Picture, each option with a plain description.
- Fixes: black stripes from contact shade on slanted ground and water, snow tint spreading over the
  whole map, torch speckles, too-bright nights, storms at night too dark to see.

## Needs

Horizon with shader API 0.2 (Nightly 2026-11-18 and later). Put the folder or
`lumora-1.3.0.hshader` in the game's `shaderpacks/` folder and pick it in Options > Video
Settings > Shaders.

## Licence

MIT (LICENSE).
