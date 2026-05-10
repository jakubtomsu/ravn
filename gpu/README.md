# Ravn GPU

This is a GPU abstraction layer which can be used independently from all the other Ravn packages.

The goal is to expose an API on a level to D3D11, but with support for multiple platforms.

Currently the following APIs are supported:
- D3D11
- WebGPU (both native and web)

Features
- Explicit pipelines, but there is internal cache for immediate-mode API
- No retained-mode creation of resources like blend modes, samplers, rasterizers states or depth stencil. It's fully immediate-mode.
- Simple validation layer