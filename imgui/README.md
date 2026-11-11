# Dear Imgui Bindings and Impl

Windows setup, requires VS developer console:
```
cd imgui
clone.cmd
build.cmd
```

In case you want to rebuild shaders, run:
```
cd ravn
odin run shaderc -- imgui\imgui_impl_gpu -targets:DXBC,WGSL -release
```
