<div align="center">

<img src="data/logo.png" width=180px>

(read as *raven*)

RAVN is a collection of lightweight libraries for game and engine development in [Odin](https://odin-lang.org).

### [Discord Link](https://discord.com/invite/wn5jMMMYe4)

</div>

> [!WARNING]
> **EARLY ALPHA VERSION**: Not stable yet. Expect major breaking changes.


## Packages

See [Cheatsheet](./CHEATSHEET.md) for quick API overview.

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
- [entities](entities/)

# Getting Started

Install [Odin](https://github.com/odin-lang/Odin) and make sure it's in your path. Check the [Official Install docs](https://odin-lang.org/docs/install/) for more info. The main RAVN branch should always compile on the latest Odin master branch.

## Project Setup
The most straightforward approach is to just clone this repo directly into your project:
```
git clone git@github.com:jakubtomsu/ravn.git
```
And then add `ravn/` into your `.gitignore` files since it's a nested repo.

### Dependencies
If you're on windows, you might not need to do any/most of this setup at all. But a complete setup looks like this:
- put `slang-compiler.dll`/`libslang.so` in your project root dir
- put `SDL3.dll` in your project root dir
- run `clone` and `build` scripts in `ravn/imgui/`

### Using git subtrees
Some people might prefer to use git subtrees instead of cloning. This is how to download the repo, and update to latest changes:
```
git subtree add --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
git subtree pull --prefix=ravn https://github.com/jakubtomsu/ravn main --squash
```

## Examples

You can run demos from the [examples/](examples) directory with something like the following command:
```
odin run examples\triangle
```

# Contributing

Most wanted type of contributions is bugfixes. Both Issues and PRs are acceptable.
Please include `odin report` output and a code sample to reproduce the issue if applicable.

If you want a new feature, it is recommended to discuss it on Discord first.

### Code style

- Keep things simple
- Ensure coherency with the rest of the code
- Use the default Odin [naming conventions](https://github.com/odin-lang/Odin/wiki/Naming-Convention)
