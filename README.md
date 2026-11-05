<div align="center">

<img src="data/logo.png" width=180px>

(read as *raven*)

RAVN is a collection of lightweight 2D and 3D libraries for game and engine development in [Odin](https://odin-lang.org).

### [Discord Link](https://discord.com/invite/wn5jMMMYe4)

</div>

> [!WARNING]
> **EARLY ALPHA VERSION**: Not stable yet. Expect major breaking changes.


## Packages

- [base](base/)
- [gpu](gpu/)
- [platform](platform/)
- [audio](audio/)
- [scene](scene/)
- [shader_compiler](shader_compiler/)
- [debugdraw](debugdraw/)
- [bvh](bvh/)
- [geometry](geometry/)
- [collision](collision/)
- [imgui](imgui/)
- [input](input/)
- [entities](input/)

# Getting Started

Install [Odin](https://github.com/odin-lang/Odin) and make sure it's in your path. Check the [Official Install docs](https://odin-lang.org/docs/install/) for more info. The main RAVN branch should always compile on the latest Odin master branch.

## Project Setup
The recommended approach is using [git subtrees](https://github.com/git/git/blob/master/contrib/subtree/git-subtree.adoc), a nicer alternative to submodules or manual copy-pasting.

Here are the commands to clone the library into your project, and to pull the latest upstream changes. It will appear just as a regular directory.
```
git subtree add --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
git subtree pull --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
```
## Examples

You can run demos from the [examples/](examples) directory with something like the following command:
```
odin run examples\hello
odin run build -- run_hot examples\hello
```

# Docs

See [Cheatsheet](./CHEATSHEET.md) for quick API overview.

## Web builds

You can run the following command to export your game to web:
```
odin run build -- export-web my_package
```
To run the app locally, you must also create a tiny HTTP file server. VSCode live server extension or `python -m http.server <port>` is recommended.

> [!NOTE]
> In case you're having issues with rendering, you can test WebGPU is behaving correctly locally with `odin run my_package -define:GPU_BACKEND=WGPU`, however the wgpu-native used on desktop can be slightly different than the Chrome Dawn implementation.

## Cross platform shaders

The engine comes with a few built-in shaders. Those always work everywhere by default.

Compiling custom shaders is handled internally using the `shader_compiler` package when you load a shader from source.
This requires a ***slang compiler dynamic library*** on non-D3D11 builds. Install it from [slang github](https://github.com/shader-slang/slang) releases.

- Windows: copy `slang.dll` and `slang-compiler.dll` into your project
- Linux: copy `libslang-compiler.so.*` as `libslang.so` into your project.



# Contributing
For info about bug reports and contributing, see [CONTRIBUTING](CONTRIBUTING.md)

