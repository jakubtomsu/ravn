#!/usr/bin/env sh

run_with_timeout() {
    # We define `timeout=` as a script global
    # To allow for more time on some examples
    setsid timeout -k 2 "$timeout" "$@" &
    pid=$!
    wait $pid
    exit_code=$?
    if [ $exit_code -eq 124 ] || [ $exit_code -eq 137 ]; then
        kill -KILL -$pid 2>/dev/null
        return 0
    elif [ $exit_code -ne 0 ]; then
        echo "Check failed with exit code: $exit_code"
        exit 1
    fi
}

set -x # Print the runned commands

# We run 3 seconds to have enough time to compile and startup most example
timeout=3

run_with_timeout odin run examples/hello
run_with_timeout odin run examples/hello -debug
run_with_timeout odin run examples/hello -define:RELEASE=true

run_with_timeout odin run examples/hello -define:AUDIO_BACKEND=None
# WASAPI (Windows Audio Session API) is not supported on Linux, without WINE / Proton
# run_with_timeout odin run examples/hello -define:AUDIO_BACKEND=WASAPI
run_with_timeout odin run examples/hello -define:AUDIO_BACKEND=miniaudio
run_with_timeout odin run examples/hello -define:AUDIO_BACKEND=SDL3

## NOTE These don't run on linux desktop, they are dummy procedures for `odin check`
# run_with_timeout odin run examples/hello -define:PLATFORM_BACKEND=Dummy
# run_with_timeout odin run examples/hello -define:GPU_BACKEND=Dummy

## NOTE These don't run on linux desktop, they are for a web environment
# run_with_timeout odin run examples/hello -define:GPU_BACKEND=WGPU -target:js_wasm32
# run_with_timeout odin run examples/hello -define:PLATFORM_BACKEND=JS -target:js_wasm32

# D3D11 (Direct3D 11) is not supported on Linux, without WINE / Proton
# run_with_timeout odin run examples/hello -define:GPU_BACKEND=D3D11
run_with_timeout odin run examples/hello -define:GPU_BACKEND=WGPU

# Windows Platform is not supported on Linux, without WINE / Proton
# run_with_timeout odin run examples/hello -define:PLATFORM_BACKEND=Windows
run_with_timeout odin run examples/hello -define:PLATFORM_BACKEND=SDL3

run_with_timeout odin run examples/hello
run_with_timeout odin run examples/hello_minimal
run_with_timeout odin run examples/audio_viewer
run_with_timeout odin run examples/geometry
run_with_timeout odin run examples/collision
run_with_timeout odin run examples/stress_test_3d
run_with_timeout odin run examples/spatial_audio
run_with_timeout odin run examples/fps

# TODO Fix examples/gpu_compute for linus
# run_with_timeout odin run examples/gpu_compute

run_with_timeout odin run examples/draw_2d

# TODO Fix examples/draw_3d for linus
# run_with_timeout odin run examples/draw_3d
#
run_with_timeout odin run examples/render_texture
run_with_timeout odin run examples/snake_planet
run_with_timeout odin run examples/standalone_audio_simple

# TODO Fix examples/standalone_gpu_sdl3_triangle for linus
# run_with_timeout odin run examples/standalone_gpu_sdl3_triangle

# D3D11 (Direct3D 11) is not supported on Linux, without WINE / Proton
# run_with_timeout odin run examples/standalone_platform_d3d11

odin test . -debug
odin test entities -debug

# examples/audio_viewer takes more time to start up
timeout=6
run_with_timeout odin run examples/audio_viewer

set +x # Stop printing runned commands
echo "All examples ran fine for at least 3 seconds!"
exit 0 # Success
