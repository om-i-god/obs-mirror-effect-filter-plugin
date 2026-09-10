# OBS Mirror Effect Filter

A mirror / kaleidoscope video filter for [OBS Studio](https://obsproject.com/), written as a
single Lua script. No compiler, no build step, no native plugin to install — drop in one file
and it appears in the Filters list on any source.

Horizontal, vertical and quad folds with a mirror line you can move and rotate freely, plus a
radial kaleidoscope mode.

## Install

1. Download `mirror-filter.lua`.
2. In OBS: **Tools → Scripts → `+`** and select the file.
3. Right-click any source → **Filters → `+` → Mirror**.

Requires an OBS build with Lua scripting enabled (the official builds have it).

## Controls

| Control | Description |
| --- | --- |
| **Mode** | `Left to right`, `Right to left`, `Top to bottom`, `Bottom to top`, `Quad`, `Kaleidoscope` |
| **Mirror X / Y** | Position of the fold line, as a percentage of the frame. Default 50 / 50. |
| **Angle** | Tilts the mirror line while the image stays upright. In `Kaleidoscope` mode it spins the pattern instead. |
| **Segments** | Wedge count for `Kaleidoscope`, 2–32. Ignored by the other modes. |
| **Transparent outside frame** | An off-centre fold samples past the edge of the source. When on, those pixels are transparent; when off, the edge pixel smears outward. |

## How it works

The whole effect is a coordinate transform in the pixel shader — the source texture is never
modified, only sampled from somewhere else.

For each output pixel:

1. Move into aspect-corrected space centred on the mirror line, so a 45° line is genuinely 45°
   on a 16:9 frame rather than skewed.
2. Rotate by `-angle` so the mirror line lands on the vertical axis.
3. Fold: reflect the coordinate across the axis (or, in kaleidoscope mode, wrap the polar angle
   into a single wedge and mirror within it).
4. Rotate back by `+angle` and undo the aspect correction, so the picture stays upright and only
   the mirror line is tilted. Kaleidoscope mode skips this step — its vector is rebuilt from
   polar coordinates, which is why `Angle` becomes a rotation control there.
5. Sample the source at the resulting coordinate.

The filter uses `OBS_NO_DIRECT_RENDERING`. This is required rather than incidental: the shader
reads texels far away from the one it is writing, so the source has to be flattened to a texture
first. Direct rendering would produce garbage on composite sources.

## Extending it

Every control maps to one shader uniform. To add a parameter:

1. Add a `uniform` to the shader string.
2. Grab it with `gs_effect_get_param_by_name` in `info.create`.
3. Set it with `gs_effect_set_float` / `gs_effect_set_int` in `info.video_render`.
4. Add the matching `obs_properties_add_*` in `info.get_properties`, a default in
   `info.get_defaults`, and a read in `info.update`.

Since the modes are pure UV math, other folds are cheap to add — a triangular fold, a
repeating tile, or driving `angle` from a timer for a slowly rotating kaleidoscope.

## Troubleshooting

If **Mirror** does not appear in the filter list, open **Tools → Scripts → Script Log**. A Lua
syntax error or a shader compile error will be reported there.
