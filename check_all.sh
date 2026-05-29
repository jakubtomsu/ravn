#!/usr/bin/env sh

handle_error() {
    set +x # Stop printing runned commands
    echo "Check failed at line $LINENO with exit code: $?"
    exit 1
}

# On any command failure, we handle it
trap handle_error ERR

set -x # Print the runned commands

odin check build
odin check build -debug

odin check examples/hello
odin check examples/hello -debug
odin check examples/hello -define:RELEASE=true

odin check examples/hello -define:AUDIO_BACKEND=None
odin check examples/hello -define:AUDIO_BACKEND=WASAPI
odin check examples/hello -define:AUDIO_BACKEND=miniaudio
odin check examples/hello -define:AUDIO_BACKEND=SDL3

odin check examples/hello -define:GPU_BACKEND=Dummy
odin check examples/hello -define:GPU_BACKEND=D3D11
odin check examples/hello -define:GPU_BACKEND=WGPU
odin check examples/hello -define:GPU_BACKEND=WGPU -target:js_wasm32

odin check examples/hello -define:PLATFORM_BACKEND=Dummy
odin check examples/hello -define:PLATFORM_BACKEND=Windows
odin check examples/hello -define:PLATFORM_BACKEND=JS -target:js_wasm32
odin check examples/hello -define:PLATFORM_BACKEND=SDL3

odin check examples/hello
odin check examples/hello_minimal
odin check examples/audio_viewer
odin check examples/geometry
odin check examples/collision
odin check examples/stress_test_3d
odin check examples/spatial_audio
odin check examples/fps
odin check examples/gpu_compute
odin check examples/draw_2d
odin check examples/draw_3d
odin check examples/render_texture
odin check examples/snake_planet
odin check examples/standalone_audio_simple
odin check examples/standalone_gpu_sdl3_triangle
odin check examples/standalone_platform_d3d11

odin test . -debug
odin test entities -debug

set +x # Stop printing runned commands
echo "All checks passed!"
exit 0 # Success
