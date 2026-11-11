# RAVN Shader Compiler

Abstracts interface to slang and d3dcompiler.

## Setup
- Windows: copy `slang-compiler.dll` into your project
- Linux: copy `libslang-compiler.so.*` as `libslang.so` into your project.

## Commandline Tool

A tool for compiling individual shader files or entire shader folders is includes.
It filters based on `vs/ps/cs.slang` file extensions.

Usage:
```
odin run shaderc -- -help
odin run shaderc -debug -- foo.vs.slang -targets:DXBC
odin run shaderc -debug -- my_shader_directory -targets:DXBC,WGSL,HLSL -release
```
