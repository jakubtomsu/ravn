<div align="center">

# RAVN

(pronounced *raven*)

### RAVN is a lightweight 2D and 3D engine framework for the joy of game development for [Odin](https://odin-lang.org).

### [Discord](https://discord.com/invite/wn5jMMMYe4)

</div>

> [!WARNING]
> ***EARLY ALPHA VERSION***
>
> Do NOT use for anything serious yet. Major features aren't fully finished and might break. There will be large breaking API changes.
>
> Windows is stable, but WASM+WebGPU or Linux builds might have bugs.



## Principles
A game library made specifically for small indie teams and fast iteration times.
Something *simple* you can prototype in, but also *stable* enough to make polishing a full game straightforward.

- Batteries-included
- Simple and hackable
- Minimal dependencies
- Code and Asset hotreloading
- Zero hidden internal state
- Modular architecture

> Inspired by Sokol, PICO8 and Raylib.

## Simple Example

```odin
import rv "ravn"
// Export app info to allow for hot reloading
@export _module_desc := rv.Module_Desc{update = _update}

main :: proc() {
    rv.run_main_loop(_module_desc)
}

_update :: proc(_: rawptr) -> rawptr {
    if rv.key_pressed(.Escape) { rv.request_shutdown() }
    // Initialize camera for layer 0
    rv.set_layer_params(0, rv.make_screen_camera(rv.get_screen_size()))
    // Set up draw state
    rv.set_draw_texture(rv.get_builtin_texture(.CGA8x8thick))
    rv.draw_text_2d("Hello World! ☺", {100, 100}, scale = 4, spacing = 1)
    // Tell the GPU to render layer 0 to default render target
    rv.render_layer(0, clear_color = rv.DARK_BLUE.rgb, clear_depth = true)
    return nil
}
```

# Getting Started

## Prequisities
Install [Odin](https://github.com/odin-lang/Odin) and make sure it's in your path. Check the [Official Install docs](https://odin-lang.org/docs/install/) for more info.

There are no additional dependencies.

## Project Setup
The recommended approach is using [git subtrees](https://github.com/git/git/blob/master/contrib/subtree/git-subtree.adoc), a nicer alternative to submodules or manual copy-pasting.

Here are the commands to clone the library into your project, and to pull the latest upstream changes. It will appear just as a regular directory.
```
git subtree add --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
git subtree pull --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
```
> In case you want to delete the entire subtree, just remove the folder. There shouldn't be any hidden metadata.

## Examples

You can run demos from the [examples/](examples) directory with something like the following command:
```
odin run examples\hello
odin run build -- run_hot examples\hello
```
Try the [hello](examples/hello/hello_example.odin) or [Snake Planet game](examples/snake_planet/snake_planet_example.odin) examples!


# Docs

## Web builds

You can run the following command to export your game to web:
```
odin run build -- export-web my_package
```
To run the app locally, you must also create a tiny HTTP file server. VSCode live server extension or `python -m http.server <port>` is recommended.

> [!NOTE]
> In case you're having issues with rendering, you can test WebGPU is behaving correctly locally with `odin run my_package -define:GPU_BACKEND=WGPU`, however the wgpu-native used on desktop can be slightly different than the Chrome Dawn implementation.


## Cheatsheet

List of most common functions in an easily searchable way.

> [!WARNING]
> INCOMPLETE/OUTDATED

### Drawing

```odin
draw_sprite(...)
draw_mesh(...)
draw_triangle(...)
draw_line(...)
draw_text(...)
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

