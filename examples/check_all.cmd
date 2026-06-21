odin check build || goto :err
odin check build -debug || goto :err

odin check examples/hello || goto :err
odin check examples/hello -debug || goto :err
odin check examples/hello -define:RELEASE=true || goto :err

odin check examples/hello -define:AUDIO_BACKEND=None || goto :err
odin check examples/hello -define:AUDIO_BACKEND=WASAPI || goto :err
odin check examples/hello -define:AUDIO_BACKEND=miniaudio || goto :err
odin check examples/hello -define:AUDIO_BACKEND=SDL3 || goto :err

odin check examples/hello -define:GPU_BACKEND=Dummy || goto :err
odin check examples/hello -define:GPU_BACKEND=D3D11 || goto :err
odin check examples/hello -define:GPU_BACKEND=WGPU || goto :err
odin check examples/hello -define:GPU_BACKEND=WGPU -target:js_wasm32 || goto :err

odin check examples/hello -define:PLATFORM_BACKEND=Dummy || goto :err
odin check examples/hello -define:PLATFORM_BACKEND=Windows || goto :err
odin check examples/hello -define:PLATFORM_BACKEND=JS -target:js_wasm32 || goto :err
odin check examples/hello -define:PLATFORM_BACKEND=SDL3 || goto :err

odin check examples/hello || goto :err
odin check examples/hello_minimal || goto :err
odin check examples/audio_viewer || goto :err
odin check examples/geometry || goto :err
odin check examples/collision || goto :err
odin check examples/stress_test_3d || goto :err
odin check examples/spatial_audio || goto :err
odin check examples/fps || goto :err
odin check examples/gpu_compute || goto :err
odin check examples/draw_2d || goto :err
odin check examples/draw_3d || goto :err
odin check examples/render_texture || goto :err
odin check examples/snake_planet || goto :err
odin check examples/standalone_audio_simple || goto :err
odin check examples/standalone_gpu_sdl3_triangle || goto :err
odin check examples/standalone_platform_d3d11 || goto :err

odin test . -debug || goto :err
odin test entities -debug || goto :err

@echo off
echo All checks passed!
exit /b 0

:err
@echo off
echo Check failed with exit code: %errorlevel%
exit /b 1