# gaea-plugin-locate

Where something is in a picture, as boxes: MES Image 0.1's `image.locate` as a
[Gaea](https://github.com/xocialize-code/gaea) plugin. It runs **Qwen3-VL-4B-Instruct** (Apache-2.0), is built on
[GaeaPluginKit](https://github.com/xocialize-code/gaea-plugin-kit) over
[mlx-locate-swift](https://github.com/xocialize/mlx-locate-swift) 0.1.0, runs in its own process, and speaks the Gaea
Plugin Protocol v1. It needs Gaea 1.9.0. Add it to Gaea by its repo URL:

```bash
gaea plugins add https://github.com/xocialize-code/gaea-plugin-locate
```

## What it offers

One model, `qwen3-vl-locate`, on `image.locate`. It is the operation's default, so a request needn't name it.

```bash
curl -s -H 'MES-Version: 0.1' -H 'Content-Type: application/json' http://localhost:7340/mes/v0/jobs \
  -d '{"operation":"image.locate","inputs":{"image":{"upload":"<id>"},"prompt":"the character'"'"'s head including the hair"}}'
```

The result's `boxes` output is a list, best first:

```json
[{"x": 0.33, "y": 0.07, "width": 0.32, "height": 0.31, "label": "the character's hair", "score": 0.42}]
```

- **Boxes** are shares of the upright picture from its top-left corner. Gaea sends the picture upright, so a photo
  with an orientation tag gives boxes of the picture as it is shown.
- **One box for each instance.** "The character's hands" gives two boxes. `count` is the most to return: 1 by default,
  at most 16.
- **Nothing found** is a success: an empty list, with the warning `nothing_found`.
- **The prompt** decides how the box is drawn. "The character's face" runs from the hairline to the chin; "the
  character's facial skin, below the bangs" gives the skin only.
- **`score`** ranks boxes. It is the model's confidence in the coordinates it wrote, not a calibrated probability
  (0.28 to 0.66 on the pictures it was measured on).
- **`label`** is the prompt.
- **No seed.** Decoding is greedy, so the same picture and prompt give the same boxes.
- **Size.** Pictures are read at up to 1024 px on the long side, so small or crowded things may be missed.

## How good it is

mlx-image measured it on the 12 illustrations mlx-3d uses for HairDeck's head crop, against SAM 3's boxes (AB-R-0879):

| Lane | Hair box IoU | Face box IoU | Head crop within tolerance | Time per query |
|---|---|---|---|---|
| `int8` | 0.917 | 0.750 | 12 of 12 | 0.63 s |
| `int4` | 0.913 | 0.721 | 11 of 12 | 0.47 s |

Medians, on an M5 Max with the GPU shared, so the times are upper bounds. "Within tolerance" is the range in which a
different head crop changes HairDeck's hair less than another seed does (AB-R-0851).

## Lanes and memory

| Lane | Artifact | Resident | Peak while running | Gaea schedules |
|---|---|---|---|---|
| `int8` (default) | `mlx-community/Qwen3-VL-4B-Instruct-8bit` | 5.4 GB | 2.6 GB | 8.0 GB |
| `int4` | `mlx-community/Qwen3-VL-4B-Instruct-4bit` | 3.35 GB | 2.6 GB | 5.95 GB |

The figures are the package's declared footprints. When `int8` doesn't fit, Gaea loads `int4` and warns
(`lane_fallback`); `gaea models lane qwen3-vl-locate int4` makes it the default. A request naming a lane
(`x-gaea.lane`) never falls back.

## Weights

Gaea sends its models root in `configure`. Each lane is its own artifact, pinned to a commit; the worker looks for it
there and downloads a missing snapshot on `prepare`. `gaea plugins warm com.xocialize.gaea.locate` does it ahead.

## How the boxes travel

The engine contract has no capability that carries boxes yet (asked of mlx-engine, AB-A-0295). The package serves
`imageAnalysis` in its `locate` mode and answers with the boxes as JSON text; the worker decodes that and returns the
list as the `boxes` output's value (GPP-1 §3.3.5). MESKit, in Gaea, keeps each box inside the picture, sorts by score
and cuts the list to `count`.

## Build and check locally

```bash
scripts/build-plugin.sh
```

```bash
CHECK_MODELS_ROOT=/path/to/models scripts/check-plugin.sh
```

`check-plugin.sh` locates the fox in `Tests/Fixtures/fox.png` over GPP on the signed bundle, with every `.build` folder
hidden so MLX can find its metallib only inside the bundle. A control then shows that the bare worker, outside the
bundle, can't. `scripts/release.sh` builds, checks, notarizes with the fleet's `mlx-notary` profile, and publishes the
GitHub release; the release workflow does the same in CI when a `v<version>` tag is pushed.

`locate-inproc` (its header lists the options) is not part of the plugin. It runs the same lane in-process through
MLXServeEngine with the plugin's own request: the reference Gaea's runs are compared against.

```bash
scripts/golden.sh <out-dir>
```

`golden.sh` finds things in the fox picture over GPP on the signed bundle and through `locate-inproc`, and needs each
pair to be the same list of boxes, number for number: the fox on both lanes, its ears with `count` 4, and a bicycle
that isn't there. The fox picture was made with FLUX.2 Klein.

## Licence

The plugin is Apache-2.0 (Gaea G-21) and ships no weights. Qwen3-VL-4B-Instruct's weights are Apache-2.0 (Alibaba
Cloud, [Qwen/Qwen3-VL-4B-Instruct](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct)); its training data is
undisclosed, so the declared licence governs (AB-D-0105). mlx-locate-swift is Apache-2.0.
