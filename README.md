<div align="center">

# RAVEN
A toolkit for making 2D and 3D games in Odin

***WARNING: EARLY ALPHA VERSION***

Do NOT use for anything serious yet. Major features aren't fully finished and might break. There will be large breaking API changes.

Windows is most stable, WASM+WebGPU builds usually work but Linux and MacOS isn't supported yet.

### [Discord](https://discord.com/invite/wn5jMMMYe4)

</div>

## Goal
A game library made specifically for small indie teams and fast iteration times.
Something *simple* you can prototype in, but also *stable* enough to make polishing a full game straightforward.

- Batteries-included
- Simple and hackable
- Minimal dependencies

Inspired by Sokol, PICO8 and Raylib.

## Features
- First-class 3D support
- Hotreloading by default
    - code, textures, models, even custom files
- Modular architecture
    - the `platform`, `gpu` and `audio` packages can be used independently from the Raven engine
- Minimal dependencies
    - the core of the engine is implemented fully from scratch, see `platform` and `gpu`
- Zero hidden internal state
    - Especially manipulating it is discouraged, but for practical reasons `@private` is strictly unused.


## Simple Example

```odin
import rv "raven"

@export _module_desc := rv.Module_Desc{
    update = _update,
}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_update :: proc(_: rawptr) -> rawptr {
    if rv.key_pressed(.Escape) { rv.request_shutdown() }

    rv.set_layer_params(0, rv.make_screen_camera())

    rv.bind_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text("Hello World! ☺", {100, 100, 0}, scale = 4, spacing = 1)

    rv.upload_gpu_layers()
    rv.render_gpu_layer(0, rv.DEFAULT_RENDER_TEXTURE,
        clear_color = rv.DARK_BLUE.rgb, clear_depth = true)

    return nil
}
```

# Getting Started

## Prequisities
Install [Odin](https://github.com/odin-lang/Odin) and make sure it's in your path. Check the [Official Install docs](https://odin-lang.org/docs/install/) for more info.

There are no additional dependencies.

## Examples

You can run demos from the [examples/](examples) directory with something like the following command:
```
odin run examples\hello
```

Alternatively you can run them in hot-reload mode:
```
odin run build -- run_hot examples\hello
```

Recommended examples:
- [hello](examples/hello/hello_example.odin)
- [simple_3d](examples/simple_3d/simple_3d_example.odin)
- [snake_planet game](examples/snake_planet/snake_planet_example.odin)

## Project Setup
The recommended approach is using [git subtrees](https://github.com/git/git/blob/master/contrib/subtree/git-subtree.adoc), a nicer alternative to submodules or manual copy-pasting.

From your project's root folder, clone the repo with this command:
```
git subtree add --prefix=raven https://github.com/jakubtomsu/raven main --squash
```

Now Raven appears just as a regular directory in your git repo, and you're good to go.

To pull the latest changes, use the following command:
```
git subtree pull --prefix=raven https://github.com/jakubtomsu/raven main --squash
```

> In case you want to delete the entire subtree, just remove the folder. There shouldn't be any hidden metadata.




## Roadmap
- Finish/Rewrite Asset system
  - Scene asset pipeline
  - Blender exporter plugin/lib
- Lightweight shader transpiler
- SDL3 platform and GPU backend as a fallback
- Finish Audio system
  - Web Audio
- Better fonts
    - Draw text iterator
    - Unicode font support (currently only CP437 atlases are supported)
- Simple GUI and gizmo system
- Geometry and Collision package
- Skinned meshes and animations
- Pakfiles


# Docs

## Hot-reload

All assets are hotreloaded automatically, just pass `watch = true` flag when loading an asset directory.

Code can be hot reloaded by running `odin run build -- run_hot my_package`.

## Web builds

You can run the following command to export your game to web:
```
odin run build -- export-web my_package
```

To run the app locally, you must also create a tiny HTTP file server (to fetch the WASM) due to CORS policy. Something like this works:
```
python -m http.server 8000
```
And now just enter `localhost:8000` into a browser search bar. Alternatively you can use the VSCode live server extension which makes this even nicer.

To see the output log, open up the Developer Tools Console (F12 usually).

In case you're having issues with rendering, you can test WebGPU is behaving correctly locally with `odin run my_package -define:GPU_BACKEND=WGPU`, however the wgpu-native used on desktop can be slightly different than the Chrome Dawn implementation.

For more detailed information see the source code directly.

## Engine Structure
- raven
  - platform - majority of OS specific code
    - win32
    - js
  - gpu - Low-level GPU Rendering layer
    - d3d11
    - wgpu
  - audio
    - miniaudio
- base - lightweight core utils with no dependencies, used by other packages
- build - tool for exporting builds and hot-reloading

## Cheatsheet

List of most common functions in an easily searchable way.

NOT COMPLETE YET

### Assets

```odin
load_asset_directory(path: string, watch: bool)
load_constant_asset_directory(#load_directory(path: string))
```

### Drawing

```odin
draw_sprite(...)
draw_mesh(...)
draw_triangle(...)
draw_line(...)
draw_text(...)
```

### Input

```odin
mouse_pos() -> [2]f32
mouse_delta() -> [2]f32
scroll_delta() -> [2]f32
key_down(key: Key) -> bool
key_down_time(key: Key) -> f32
key_pressed(key: Key, buf: f32 = 0) -> bool
key_repeated(key: Key) -> bool
key_released(key: Key) -> bool
mouse_down(button: Mouse_Button) -> bool
mouse_down_time(button: Mouse_Button) -> f32
mouse_pressed(button: Mouse_Button, buf: f32 = 0) -> bool
mouse_repeated(button: Mouse_Button) -> bool
mouse_released(button: Mouse_Button) -> bool
```

### Sounds
```odin
play_sound(resource: Sound_Resource_Handle, ...) -> Sound_Handle
```

### Utils
```odin
deg(degrees: f32) -> f32                    // Convert degrees to radians
lerp(a, b: $T, t: f32) -> T                 // Linearly interpolate between A and B
lexp(a, b: $T, rate: f32) -> T              // Exponential lerp for things like 'a = lexp(a, target, delta*10)'
fade(alpha: f32) -> Vec4                    // Make a white color with a given alpha value
gray(val: f32) -> Vec4                      // Value = 0 means black, = 1 means white
vcast($T: typeid, v: [$N]$E) -> [N]T        // Cast from one type of vector to another
rot90(v: [2]$T) -> [2]T                     // Rotate a 2D vector 90 degrees counter-clockwise
unlerp(a, b: f32, x: f32) -> T              // Map x from range a..b to 0..1
remap(x, a0, a1, b0, b1: f32) -> f32        // Map x from range a0..a1 to b0..b1
smoothstep(edge0, edge1, x: f32) -> f32     // Generates a smooth curve from x in range edge0..edge1
oklerp(a, b: Vec4, t: f32) -> Vec4          // Interpolate colors with OKLAB
```



# Contributing
For info about bug reports and contributing, see [CONTRIBUTING](CONTRIBUTING.md)

