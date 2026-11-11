package ravn_examples_all

import "core:fmt"

main :: proc() {
    fmt.println("This is just a stub package which imports everything in RAVN for easy 'odin check' and 'odin test'")
}

@(require) import "../base"
@(require) import "../platform"
@(require) import "../gpu"
@(require) import "../audio"
@(require) import "../audio/qoa"
@(require) import "../audio/wav"
@(require) import "../bvh"
@(require) import "../collision"
@(require) import "../curve"
@(require) import "../debugdraw"
@(require) import "../util"
@(require) import "../input"
@(require) import "../entities"
// @(require) import "../build"

@(require) import audio_simple_example "audio_simple"
@(require) import debugdraw_example "debugdraw"
@(require) import imgui_example "imgui"
@(require) import triangle_example "triangle"
@(require) import triangle_gpu_sdl3_example "triangle_gpu_sdl3"
