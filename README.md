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

Requires an OBS build with Lua scripting enabled (the official builds have it). Nothing runs in
the background — OBS loads the script and registers the filter type on every launch.

## Controls

| Control | Description |
| --- | --- |
| **Mode** | `Left to right` / `Right to left` fold across a vertical seam, `Top to bottom` / `Bottom to top` across a horizontal seam, `Quad` folds both axes at once, `Kaleidoscope` is a radial fold. |
| **Mirror X / Y** | Position of the fold line, as a percentage of the frame. Default 50 / 50. |
| **Angle** | Tilts the mirror line while the image stays upright. In `Kaleidoscope` mode it spins the pattern instead. |
| **Segments** | Wedge count for `Kaleidoscope`, 2–32. Ignored by the other modes. |
| **Outside frame** | What happens when an off-centre fold samples past the edge of the source. `Reflect` (default) folds the coordinate back in, so the frame can never go blank. `Stretch edge pixels` smears the edge outward. `Transparent` blanks those pixels. |

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
5. Resolve the coordinate against the **Outside frame** setting, then sample the source.

The filter uses `OBS_NO_DIRECT_RENDERING`. This is required rather than incidental: the shader
reads texels far away from the one it is writing, so the source has to be flattened to a texture
first. Direct rendering would produce garbage on composite sources.

### Sizing the render target

`info.video_render` needs the dimensions of whatever it sits on top of, and getting this wrong
is the single easiest way to break an OBS filter. `obs_source_get_base_width()` is the obvious
call, but it returns **0 for async sources** — cameras (`dshow_input`), media files
(`ffmpeg_source`) and VLC sources. A filter that bails out on a zero size will emit a fully
transparent frame on exactly those sources while working perfectly on a scene, whose base size
is always the canvas.

`target_size()` therefore tries three things in order: `obs_source_get_base_width`, then
`obs_source_get_width`, then the canvas via `obs_get_video_info`.

## Extending it

Every control maps to one shader uniform. To add a parameter:

1. Add a `uniform` to the shader string.
2. Grab it with `gs_effect_get_param_by_name` in `info.create`.
3. Set it with `gs_effect_set_float` / `gs_effect_set_int` in `info.video_render`.
4. Add the matching `obs_properties_add_*` in `info.get_properties`, a default in
   `info.get_defaults`, and a read in `info.update`.

Since the modes are pure UV math, other folds are cheap to add — a triangular fold, a
repeating tile, or driving `angle` from a timer for a slowly rotating kaleidoscope.

If you add a uniform, add its handle to the validation check in `info.create` too. A nil
parameter handle throws partway through `video_render`, between `process_filter_begin` and
`process_filter_end`, which leaves the render target untouched and emits a transparent frame —
a confusing failure that looks like a black screen rather than an error.

## Troubleshooting

If **Mirror** does not appear in the filter list, open **Tools → Scripts → Script Log**. A Lua
syntax error or a shader compile error will be reported there.

**The frame goes completely blank.** Two causes, both fixed in the current version:

- *Applied to a camera or media source.* See [Sizing the render target](#sizing-the-render-target)
  — async sources report a base size of 0 and older versions skipped rendering entirely.
- *Mirror X or Y dragged to an extreme.* With the old `Transparent outside frame` default, a
  fold near the edge pushed every sampled pixel outside the source, so the whole frame went
  transparent — and because the pivot is saved into the scene collection, it stayed that way
  across restarts. `Outside frame` now defaults to `Reflect`, which cannot blank.

**Quad mode looks like it only folds one way.** Check what you are pointing at. On a test
pattern made of vertical colour bars there is no vertical variation, so the horizontal fold
changes nothing visible — it is doing the work, the image just cannot show it. Aim at something
with detail on both axes.

**Note on logging.** `obs.script_log()` writes only to the Script Log *window*, never to the OBS
log file on disk, so a misbehaving script filter leaves no trace in `%APPDATA%\obs-studio\logs`.
When debugging, write to a file directly from the script.

## License

MIT — see [LICENSE](LICENSE).
