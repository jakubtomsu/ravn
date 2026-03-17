#+vet explicit-allocators shadowing
#+build !js
package raven_gpu

import "../base"

import "base:runtime"
import "core:sys/windows"
import d3d "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

// https://www.gamedevs.org/uploads/efficient-buffer-management.pdf
// TODO: all input constraints must be spelled out at the top if each proc in gpu.odin.

when BACKEND == BACKEND_D3D11 {

    _SAMPLER_CACHE_BUCKET :: 8
    _RASTERIZER_CACHE_BUCKET :: 8
    _BLEND_CACHE_BUCKET :: 32

    _State :: struct {
        device:                 ^d3d.IDevice,
        device_context:         ^d3d.IDeviceContext,
        dxgi_factory:           ^dxgi.IFactory2,
        swapchain:              ^dxgi.ISwapChain1,
        render_texture:         ^d3d.ITexture2D,
        render_texture_view:    ^d3d.IRenderTargetView,

        info_queue:             ^d3d.IInfoQueue,

        depth_stencil_cache:    [Comparison_Op][2]_Depth_Stencil, // no need for buckets
        sampler_cache:          [Filter][Texture_Bounds]Bucket(_SAMPLER_CACHE_BUCKET, Sampler_Desc, _Sampler), // filter, bounds x
        rasterizer_cache:       [Cull_Mode][Fill_Mode]Bucket(_RASTERIZER_CACHE_BUCKET, _Rasterizer_Desc, _Rasterizer),
        blend_cache:            Bucket(_BLEND_CACHE_BUCKET, [RENDER_TEXTURE_BIND_SLOTS]Blend_Desc, _Blend),
    }

    _Pipeline :: struct {

    }

    _Compute_Pipeline :: struct {

    }

    _Sampler :: struct {
        smp:    ^d3d.ISamplerState,
    }

    _Depth_Stencil :: struct {
        dss:    ^d3d.IDepthStencilState,
    }

    _Blend :: struct {
        bs:     ^d3d.IBlendState,
    }

    _Rasterizer :: struct {
        rs:     ^d3d.IRasterizerState,
    }

    _Rasterizer_Desc :: struct {
        cull:       Cull_Mode,
        fill:       Fill_Mode,
        depth_bias: i32,
    }

    _Resource :: struct {
        srv:    ^d3d.IShaderResourceView,
        uav:    ^d3d.IUnorderedAccessView,
        using _: struct #raw_union {
            res:    ^d3d.IResource, // shared
            using _: struct {
                tex2d:  ^d3d.ITexture2D,
                rtv:    ^d3d.IRenderTargetView,
                dsv:    ^d3d.IDepthStencilView,
            },
            tex3d:  ^d3d.ITexture3D,
            using _: struct {
                buf:    ^d3d.IBuffer,
                const_buf_data: []byte,
            },
        },
    }

    _Shader :: struct {
        using _: struct #raw_union {
            vs: ^d3d.IVertexShader,
            ps: ^d3d.IPixelShader,
            cs: ^d3d.IComputeShader,
        },
    }

    _Constants :: struct {
        cbuf:   ^d3d.IBuffer,
    }


    _init :: proc(native_window: rawptr) -> bool {
        base_device: ^d3d.IDevice
        base_device_context: ^d3d.IDeviceContext

        feature_levels := [?]d3d.FEATURE_LEVEL{._11_1}
        device_flags: d3d.CREATE_DEVICE_FLAGS = {
            .SINGLETHREADED,
            .BGRA_SUPPORT,
        }

        if !RELEASE {
            device_flags += {.DEBUG}
        }

        if !_d3d11_check(d3d.CreateDevice(
            pAdapter = nil,
            DriverType = .HARDWARE,
            Software = nil,
            Flags = device_flags,
            pFeatureLevels = &feature_levels[0],
            FeatureLevels = len(feature_levels),
            SDKVersion = d3d.SDK_VERSION,
            ppDevice = &base_device,
            pFeatureLevel = nil,
            ppImmediateContext = &base_device_context,
        )) {
            base.log_err("Failed to create D3D11 device")
            return false
        }

        _d3d11_check(base_device->QueryInterface(d3d.IDevice_UUID, cast(^rawptr)&_state.device)) or_return
        _d3d11_check(base_device_context->QueryInterface(d3d.IDeviceContext_UUID, cast(^rawptr)&_state.device_context)) or_return

        dxgi_device: ^dxgi.IDevice1
        _d3d11_check(_state.device->QueryInterface(dxgi.IDevice1_UUID, cast(^rawptr)&dxgi_device)) or_return

        dxgi_adapter: ^dxgi.IAdapter
        _d3d11_check(dxgi_device->GetAdapter(&dxgi_adapter)) or_return

        _d3d11_check(dxgi_adapter->GetParent(dxgi.IFactory2_UUID, cast(^rawptr)&_state.dxgi_factory)) or_return

        // TODO: investigate more
        _d3d11_check(dxgi_device->SetMaximumFrameLatency(1)) or_return

        if !RELEASE {
            _d3d11_check(_state.device->QueryInterface(d3d.IInfoQueue_UUID, cast(^rawptr)&_state.info_queue)) or_return
        }

        _d3d11_messages()

        _state.init_done = true

        return true
    }

    _shutdown :: proc() {
        // _state.dxgi_factory->Release()
        _state.device_context->Release()
        _state.device->Release()
        _d3d11_messages()
    }

    _begin_frame :: proc() -> bool {
        _d3d11_messages()
        _unbind_cs_rw_resources()
        _unbind_index_buffer()
        _unbind_resources({.Vertex, .Pixel, .Compute})
        _unbind_constants({.Vertex, .Pixel, .Compute})
        _unbind_samplers({.Vertex, .Pixel, .Compute})
        return true
    }

    _end_frame :: proc(sync: bool) {
        assert(_state.swapchain != nil)
        _state.swapchain->Present(sync ? 1 : 0, {})

        _d3d11_messages()
    }



    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Create
    //

    _create_pipeline :: proc(name: string, desc: Pipeline_Desc) -> (result: _Pipeline, ok: bool) {
        return {}, true
    }

    _create_compute_pipeline :: proc(name: string, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline, ok: bool) {
        return {}, true
    }

    _create_rasterizer :: proc(desc: _Rasterizer_Desc) -> (result: _Rasterizer) {
        base.log_debug("GPU: Creating D3D11 rasterizer")

        rasterizer_desc := d3d.RASTERIZER_DESC{
            FillMode                = _d3d11_fill_mode(desc.fill),
            CullMode                = _d3d11_cull_mode(desc.cull),
            FrontCounterClockwise   = true, // WARNING
            DepthBias               = desc.depth_bias,
            DepthBiasClamp          = 0,
            SlopeScaledDepthBias    = 0,
            DepthClipEnable         = true,
            ScissorEnable           = false,
            MultisampleEnable       = false,
            AntialiasedLineEnable   = false,
        }

        _d3d11_check(_state.device->CreateRasterizerState(&rasterizer_desc, &result.rs))

        _d3d11_messages()

        return result
    }

    _create_depth_stencil :: proc(comparison: Comparison_Op, write: bool) -> (result: _Depth_Stencil) {
        base.log_debug("GPU: Creating D3D11 depth stencil")

        enable := true

        depth_stencil_desc := d3d.DEPTH_STENCIL_DESC{
            DepthEnable         = d3d.BOOL(_depth_enable(comparison, write)),
            DepthWriteMask      = _d3d11_depth_write(write),
            DepthFunc           = _d3d11_comparison(comparison),
            StencilEnable       = false,
            StencilReadMask     = d3d.DEFAULT_STENCIL_READ_MASK,
            StencilWriteMask    = d3d.DEFAULT_STENCIL_WRITE_MASK,
            FrontFace = {
                StencilPassOp       = .KEEP,
                StencilFailOp       = .KEEP,
                StencilDepthFailOp  = .KEEP,
                StencilFunc         = .ALWAYS,
            },
            BackFace = {
                StencilPassOp       = .KEEP,
                StencilFailOp       = .KEEP,
                StencilDepthFailOp  = .KEEP,
                StencilFunc         = .ALWAYS,
            },
        }

        _d3d11_check(_state.device->CreateDepthStencilState(&depth_stencil_desc, &result.dss))

        _d3d11_messages()

        return result
    }


    _create_sampler :: proc(desc: Sampler_Desc) -> (result: _Sampler) {
        base.log_debug("GPU: Creating D3D11 sampler")

        desc := d3d.SAMPLER_DESC{
            Filter          = _d3d11_filter(desc.filter),
            AddressU        = _d3d11_texture_bounds(desc.bounds.x),
            AddressV        = _d3d11_texture_bounds(desc.bounds.y),
            AddressW        = _d3d11_texture_bounds(desc.bounds.z),
            MinLOD          = desc.mip_min,
            MaxLOD          = desc.mip_max,
            MipLODBias      = desc.mip_bias,
            ComparisonFunc  = _d3d11_comparison(desc.comparison),
            BorderColor     = {},
            MaxAnisotropy   = u32(clamp(desc.max_aniso, 1, 16)),
        }

        _d3d11_check(_state.device->CreateSamplerState(&desc, &result.smp))

        _d3d11_messages()

        return result
    }

    _create_blend :: proc(descs: [RENDER_TEXTURE_BIND_SLOTS]Blend_Desc) -> (result: _Blend) {
        base.log_debug("GPU: Creating D3D11 blend state")

        if descs == {} {
            return {}
        }

        blend_desc := d3d.BLEND_DESC{
            AlphaToCoverageEnable = false,
            IndependentBlendEnable = true,
        }

        for desc, i in descs {
            blend_desc.RenderTarget[i] = _d3d11_blend_desc(desc)
        }

        _d3d11_check(_state.device->CreateBlendState(&blend_desc, &result.bs))

        _d3d11_messages()

        return result

        _d3d11_blend_desc :: proc(desc: Blend_Desc) -> d3d.RENDER_TARGET_BLEND_DESC {
            return d3d.RENDER_TARGET_BLEND_DESC{
                BlendEnable             = true,
                SrcBlend                = _d3d11_blend_factor(desc.src_color),
                DestBlend               = _d3d11_blend_factor(desc.dst_color),
                BlendOp                 = _d3d11_blend_op(desc.op_color),
                SrcBlendAlpha           = _d3d11_blend_factor(desc.src_alpha),
                DestBlendAlpha          = _d3d11_blend_factor(desc.dst_alpha),
                BlendOpAlpha            = _d3d11_blend_op(desc.op_alpha),
                RenderTargetWriteMask   = u8(d3d.COLOR_WRITE_ENABLE_ALL),
            },
        }
    }

    _update_swapchain :: proc(swapchain: ^_Resource, window: rawptr, size: [2]i32) -> (ok: bool) {
        assert(swapchain != nil)
        assert(size.x > 0)
        assert(size.y > 0)
        assert(_state.device != nil)
        assert(_state.device_context != nil)

        if _state.swapchain == nil {
            swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
                Width  = u32(size.x),
                Height = u32(size.y),
                Format = .B8G8R8A8_UNORM,
                Stereo = false,
                SampleDesc = {Count = 1, Quality = 0},
                BufferUsage = {.RENDER_TARGET_OUTPUT},
                BufferCount = 2,
                Scaling = .STRETCH,
                SwapEffect = .FLIP_DISCARD,
                AlphaMode = .UNSPECIFIED,
                Flags = {},
            }

            _d3d11_check(_state.dxgi_factory->CreateSwapChainForHwnd(
                _state.device, dxgi.HWND(window), &swapchain_desc, nil, nil, &_state.swapchain,
            )) or_return

        } else {
            _state.device_context->OMSetRenderTargets(0, nil, nil)
            _state.device_context->Flush()
            if swapchain.tex2d != nil {
                swapchain.tex2d->Release()
            }

            if swapchain.rtv != nil {
                swapchain.rtv->Release()
            }

            _d3d11_check(_state.swapchain->ResizeBuffers(
                BufferCount = 0,
                Width  = u32(size.x),
                Height = u32(size.y),
                NewFormat = .UNKNOWN,
                SwapChainFlags = {},
            )) or_return
        }

        _d3d11_messages()

        _d3d11_check(_state.swapchain->GetBuffer(0, d3d.ITexture2D_UUID, cast(^rawptr)&swapchain.tex2d)) or_return
        _d3d11_check(_state.device->CreateRenderTargetView(swapchain.tex2d, nil, &swapchain.rtv)) or_return
        _d3d11_setlabel(swapchain.tex2d, "Swapchain")

        viewports := [1]d3d.VIEWPORT{
            {
                Width  = f32(size.x),
                Height = f32(size.y),
                MinDepth = 0,
                MaxDepth = 1,
            },
        }
        _state.device_context->RSSetViewports(len(viewports), &viewports[0])

        _d3d11_messages()

        return true
    }

    // data: DXBC bytecode
    _create_shader :: proc(name: string, data: []u8, kind: Shader_Kind) -> (result: _Shader, ok: bool) {
        switch kind {
        case .Invalid:
            unreachable()

        case .Vertex:
            _d3d11_check(_state.device->CreateVertexShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppVertexShader = &result.vs,
            )) or_return

            _d3d11_setlabel(result.vs, name)

        case .Pixel:
            _d3d11_check(_state.device->CreatePixelShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppPixelShader = &result.ps,
            )) or_return

            _d3d11_setlabel(result.ps, name)

        case .Compute:
            _d3d11_check(_state.device->CreateComputeShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppComputeShader = &result.cs,
            )) or_return

            _d3d11_setlabel(result.cs, name)
        }

        _d3d11_messages()

        return result, true
    }


    _create_buffer :: proc(
        name:   string,
        size:   i32,
        stride: i32,
        usage:  Usage,
        data:   []u8,
    ) -> (result: _Resource, ok: bool) {
        bind_flags: d3d.BIND_FLAGS = {.SHADER_RESOURCE}

        desc := d3d.BUFFER_DESC{
            ByteWidth           = u32(size),
            StructureByteStride = u32(stride),
            Usage               = _d3d11_usage(usage),
            BindFlags           = bind_flags,
            CPUAccessFlags      = _d3d11_cpu_access(usage),
            MiscFlags           = {.BUFFER_STRUCTURED},
        }

        initial_data := d3d.SUBRESOURCE_DATA{
            pSysMem = raw_data(data),
        }

        initial_data_ptr: ^d3d.SUBRESOURCE_DATA
        if data != nil {
            initial_data_ptr = &initial_data
        }

        _d3d11_check(_state.device->CreateBuffer(&desc, initial_data_ptr, &result.buf)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.buf, name)

        _d3d11_check(_state.device->CreateShaderResourceView(result.buf, nil, &result.srv)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.srv, name)

        return result, true
    }

    _create_index_buffer :: proc(
        name:   string,
        size:   i32,
        data:   []u8,
        usage:  Usage,
    ) -> (result: _Resource, ok: bool) {
        bind_flags: d3d.BIND_FLAGS = {.INDEX_BUFFER}

        desc := d3d.BUFFER_DESC{
            ByteWidth = u32(size),
            Usage = _d3d11_usage(usage),
            BindFlags = bind_flags,
            CPUAccessFlags = _d3d11_cpu_access(usage),
        }

        initial_data := d3d.SUBRESOURCE_DATA{
            pSysMem = raw_data(data),
        }

        initial_data_ptr: ^d3d.SUBRESOURCE_DATA
        if data != nil {
            initial_data_ptr = &initial_data
        }

        _d3d11_check(_state.device->CreateBuffer(&desc, initial_data_ptr, &result.buf)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.buf, name)

        return result, true
    }


    _create_constants :: proc(name: string, item_size: i32, item_num: i32) -> (result: _Resource, ok: bool) {
        // Create a single buffer and rely on driver buffer renaming.

        desc := d3d.BUFFER_DESC{
            ByteWidth = u32(item_size),
            Usage = .DYNAMIC,
            BindFlags = {.CONSTANT_BUFFER},
            CPUAccessFlags = {.WRITE},
        }

        _d3d11_check(_state.device->CreateBuffer(&desc, nil, &result.buf)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.buf, name)

        return result, true
    }

    _create_texture_2d :: proc(
        name:               string,
        format:             Texture_Format,
        usage:              Usage,
        size:               [2]i32,
        mips:               i32,
        array_depth:        i32,
        render_texture:      bool,
        rw_resource:        bool,
        data:               []byte,
    ) -> (result: _Resource, ok: bool) {
        bind_flags: d3d.BIND_FLAGS

        if render_texture {
            if texture_format_is_depth_stencil(format) {
                bind_flags = {.DEPTH_STENCIL}
            } else {
                bind_flags = {.RENDER_TARGET, .SHADER_RESOURCE}
            }
        } else {
            bind_flags = {.SHADER_RESOURCE}
        }

        if rw_resource {
            bind_flags += {.UNORDERED_ACCESS}
        }

        desc := d3d.TEXTURE2D_DESC{
            Format = _d3d11_texture_format(format),
            Usage = _d3d11_usage(usage),
            Width = u32(size.x),
            Height = u32(size.y),
            ArraySize = u32(array_depth),
            MipLevels = u32(mips),
            SampleDesc = {
                Count = 1,
                Quality = 0,
            },
            CPUAccessFlags = _d3d11_cpu_access(usage),
            BindFlags = bind_flags,
            MiscFlags = {},
        }

        initial_data := d3d.SUBRESOURCE_DATA{
            pSysMem = raw_data(data),
            SysMemPitch = u32(size.x * texture_pixel_size(format)),
        }

        initial_data_ptr: ^d3d.SUBRESOURCE_DATA
        if data != nil {
            initial_data_ptr = &initial_data
        }

        _d3d11_check(_state.device->CreateTexture2D(&desc, initial_data_ptr, &result.tex2d)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.tex2d, name)

        // TODO: SRV for depth buf
        if texture_format_is_depth_stencil(format) {
            _d3d11_check(_state.device->CreateDepthStencilView(result.tex2d, nil, &result.dsv)) or_return

            _d3d11_setlabel(result.dsv, name)

        } else if render_texture {
            _d3d11_check(_state.device->CreateRenderTargetView(result.tex2d, nil, &result.rtv)) or_return

            srv_desc := d3d.SHADER_RESOURCE_VIEW_DESC{
                Format = _d3d11_texture_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                },
            }

            _d3d11_check(_state.device->CreateShaderResourceView(result.tex2d, &srv_desc, &result.srv)) or_return
            _d3d11_setlabel(result.srv, name)

        } else {
            srv_desc := d3d.SHADER_RESOURCE_VIEW_DESC{
                Format = _d3d11_texture_format(format),
                ViewDimension = .TEXTURE2DARRAY,
                Texture2DArray = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                    FirstArraySlice = 0,
                    ArraySize = u32(array_depth),
                },
            }

            _d3d11_check(_state.device->CreateShaderResourceView(result.tex2d, &srv_desc, &result.srv)) or_return
            _d3d11_setlabel(result.srv, name)
        }

        _d3d11_messages()

        if rw_resource {
            uav_desc := d3d.UNORDERED_ACCESS_VIEW_DESC{
                Format = _d3d11_texture_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {
                    MipSlice = 0,
                },
            }

            _d3d11_check(_state.device->CreateUnorderedAccessView(result.tex2d, &uav_desc, &result.uav)) or_return
            _d3d11_setlabel(result.uav, name)
        }

        _d3d11_messages()

        return result, true
    }



    // _generate_mips_texture_2d :: proc(res: Resource) {
    //     _state.device_context->GenerateMips(res.srv)
    // }




    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Destroy
    //

    _destroy_rasterizer :: proc(rasterizer: _Rasterizer) {
        rasterizer.rs->Release()
        _d3d11_messages()
    }

    _destroy_depth_stencil :: proc(depth_stencil: _Depth_Stencil) {
        depth_stencil.dss->Release()
        _d3d11_messages()
    }

    _destroy_sampler :: proc(sampler: _Sampler) {
        sampler.smp->Release()
        _d3d11_messages()
    }

    _destroy_blend :: proc(blend: _Blend) {
        blend.bs->Release()
        _d3d11_messages()
    }

    _destroy_shader :: proc(shader: Shader_State) {
        switch shader.kind {
        case .Invalid:
            return

        case .Vertex:
            shader.vs->Release()

        case .Pixel:
            shader.ps->Release()

        case .Compute:
            shader.cs->Release()
        }

        _d3d11_messages()
    }

    _destroy_resource :: proc(res: Resource_State) {
        switch res.kind {
        case .Invalid, .Swapchain:
            assert(false)
            return

        case .Buffer, .Constants, .Index_Buffer:
            res.buf->Release()

        case .Texture2D:
            res.tex2d->Release()

            if res.dsv != nil {
                res.dsv->Release()
            }

            if res.rtv != nil {
                res.rtv->Release()
            }

        case .Texture3D:
            unimplemented()
        }

        if res.srv != nil {
            res.srv->Release()
        }

        if res.uav != nil {
            res.uav->Release()
        }

        _d3d11_messages()
    }



    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Set
    //

    _set_topology :: proc(topo: Topology) {
        _state.device_context->IASetPrimitiveTopology(_d3d11_topology(topo))

        _d3d11_messages()
    }

    _set_depth_stencil :: proc(depth_stencil: _Depth_Stencil) {
        _state.device_context->OMSetDepthStencilState(depth_stencil.dss, 0)

        _d3d11_messages()
    }

    // TODO: independent blend
    _set_blend :: proc(blend: _Blend) {
        _state.device_context->OMSetBlendState(
            pBlendState = blend.bs,
            BlendFactor = nil,
            SampleMask = 0xffff_ffff,
        )

        _d3d11_messages()
    }

    _set_rasterizer :: proc(rasterizer: _Rasterizer) {
        _state.device_context->RSSetState(rasterizer.rs)

        _d3d11_messages()
    }

    _set_shader :: proc(shader: Shader_State) {
        // NOTE: no unbinding yet

        switch shader.kind {
        case .Invalid:
            assert(false)
            return

        case .Vertex:
            _state.device_context->VSSetShader(shader.vs, nil, 0)

        case .Pixel:
            _state.device_context->PSSetShader(shader.ps, nil, 0)

        case .Compute:
            _state.device_context->CSSetShader(shader.cs, nil, 0)
        }

        _d3d11_messages()
    }

    _set_resources :: proc(shaders: bit_set[Shader_Kind], srvs: []^d3d.IShaderResourceView, start_slot: i32) {
        if .Vertex in shaders {
            _state.device_context->VSSetShaderResources(
                StartSlot = u32(start_slot),
                NumViews = u32(len(srvs)),
                ppShaderResourceViews = raw_data(srvs),
            )
        }

        if .Pixel in shaders {
            _state.device_context->PSSetShaderResources(
                StartSlot = u32(start_slot),
                NumViews = u32(len(srvs)),
                ppShaderResourceViews = raw_data(srvs),
            )
        }

        if .Compute in shaders {
            _state.device_context->CSSetShaderResources(
                StartSlot = u32(start_slot),
                NumViews = u32(len(srvs)),
                ppShaderResourceViews = raw_data(srvs),
            )
        }

        _d3d11_messages()
    }

    _set_cs_rw_resources :: proc(uavs: []^d3d.IUnorderedAccessView, start_slot: i32) {
        _state.device_context->CSSetUnorderedAccessViews(
            StartSlot = u32(start_slot),
            NumUAVs = u32(len(uavs)),
            ppUnorderedAccessViews = raw_data(uavs),
            pUAVInitialCounts = nil,
        )
    }


    _set_constants :: proc(shaders: bit_set[Shader_Kind], cbufs: []^d3d.IBuffer, index_offset: i32) {
        if .Vertex in shaders {
            _state.device_context->VSSetConstantBuffers(
                StartSlot = u32(index_offset),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
            )
        }

        if .Pixel in shaders {
            _state.device_context->PSSetConstantBuffers(
                StartSlot = u32(index_offset),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
            )
        }

        if .Compute in shaders {
            _state.device_context->CSSetConstantBuffers(
                StartSlot = u32(index_offset),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
            )
        }
    }

    _set_samplers :: proc(shaders: bit_set[Shader_Kind], smps: []^d3d.ISamplerState, index_offset: i32) {
        if .Vertex in shaders {
            _state.device_context->VSSetSamplers(
                StartSlot = u32(index_offset),
                NumSamplers = u32(len(smps)),
                ppSamplers = raw_data(smps),
            )
        }

        if .Pixel in shaders {
            _state.device_context->PSSetSamplers(
                StartSlot = u32(index_offset),
                NumSamplers = u32(len(smps)),
                ppSamplers = raw_data(smps),
            )
        }

        if .Compute in shaders {
            _state.device_context->PSSetSamplers(
                StartSlot = u32(index_offset),
                NumSamplers = u32(len(smps)),
                ppSamplers = raw_data(smps),
            )
        }
    }

    _set_index_buffer :: proc(res: _Resource, format: Index_Format, offset: i32) {
        _state.device_context->IASetIndexBuffer(
            pIndexBuffer = res.buf,
            Format = _d3d11_index_format(format),
            Offset = u32(offset),
        )

        _d3d11_messages()
    }

    _unbind_cs_rw_resources :: proc() {
        uavs: [RW_RESOURCE_BIND_SLOTS]^d3d.IUnorderedAccessView
        _state.device_context->CSSetUnorderedAccessViews(0, len(uavs), &uavs[0], nil)
    }

    _unbind_index_buffer :: proc() {
        _state.device_context->IASetIndexBuffer(nil, .R32_UINT, 0)
    }

    _unbind_resources :: proc(shaders: bit_set[Shader_Kind]) {
        srvs: [RESOURCE_BIND_SLOTS]^d3d.IShaderResourceView
        if .Vertex in shaders do _state.device_context->VSSetShaderResources(0, len(srvs), &srvs[0])
        if .Pixel in shaders do _state.device_context->PSSetShaderResources(0, len(srvs), &srvs[0])
        if .Compute in shaders do _state.device_context->CSSetShaderResources(0, len(srvs), &srvs[0])
    }

    _unbind_constants :: proc(shaders: bit_set[Shader_Kind]) {
        cbufs: [CONSTANTS_BIND_SLOTS]^d3d.IBuffer
        if .Vertex in shaders do _state.device_context->VSSetConstantBuffers(0, len(cbufs), &cbufs[0])
        if .Pixel in shaders do _state.device_context->PSSetConstantBuffers(0, len(cbufs), &cbufs[0])
        if .Compute in shaders do _state.device_context->CSSetConstantBuffers(0, len(cbufs), &cbufs[0])
    }

    _unbind_samplers :: proc(shaders: bit_set[Shader_Kind]) {
        smps: [SAMPLER_BIND_SLOTS]^d3d.ISamplerState
        if .Vertex in shaders do _state.device_context->VSSetSamplers(0, len(smps), &smps[0])
        if .Pixel in shaders do _state.device_context->PSSetSamplers(0, len(smps), &smps[0])
        if .Compute in shaders do _state.device_context->CSSetSamplers(0, len(smps), &smps[0])
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Actions
    //

    _begin_pass :: proc(name: string, desc: Pass_Desc) {
        rtvs: [d3d.SIMULTANEOUS_RENDER_TARGET_COUNT]^d3d.IRenderTargetView
        dsv: ^d3d.IDepthStencilView

        if depth, depth_ok := get_internal_resource(desc.depth.resource); depth_ok {
            assert(depth.kind == .Texture2D)
            assert(depth.dsv != nil)

            dsv = depth.dsv

            switch desc.depth.clear_mode {
            case .Keep:
            case .Clear:
                _clear_depth_texture(depth, desc.depth.clear_val)
            }
        }

        resolution: [2]i32
        for color, i in desc.colors {
            res := get_internal_resource(color.resource) or_continue

            #partial switch res.kind {
            case .Texture2D:
            case .Swapchain:
            case:
                assert(false)
            }
            assert(res.rtv != nil)

            rtvs[i] = res.rtv

            resolution = res.size.xy

            switch color.clear_mode {
            case .Keep:
            case .Clear:
                _clear_render_texture(res, color.clear_val)
            }
        }

        _state.device_context->OMSetRenderTargets(
            NumViews = u32(len(rtvs)),
            ppRenderTargetViews = &rtvs[0],
            pDepthStencilView = dsv,
        )

        // NOTE: currently the viewport is tied to RT for simplicity.
        // This might get changed in the future.


        viewport := d3d.VIEWPORT{
            TopLeftX = 0,
            TopLeftY = 0,
            Width = f32(resolution.x),
            Height = f32(resolution.y),
            MinDepth = 0.0,
            MaxDepth = 1.0,
        }

        _state.device_context->RSSetViewports(1, &viewport)
    }

    _end_pass :: proc() {
        // no-op
    }

    // This is really ugly...
    _bind_pipeline :: proc(
        curr_pip: Pipeline_State,
        curr: Pipeline_Desc,
        prev: Pipeline_Desc,
    ) {
        if curr.topo != prev.topo {
            _set_topology(curr.topo)
        }

        if curr.index != prev.index && curr.index.format != .Invalid {
            res, res_ok := get_internal_resource(curr.index.resource)
            assert(res_ok)
            assert(res.kind == .Index_Buffer)
            _set_index_buffer(res, curr.index.format, curr.index.offset)
        }

        if curr.blends == {} {
            _set_blend({})
        } else if curr.blends != prev.blends {
            bucket := &_state.blend_cache
            blend := bucket_find_or_create(bucket, curr.blends, _create_blend)
            _set_blend(blend)
        }

        if curr.cull != prev.cull || curr.fill != prev.fill || curr.depth_bias != prev.depth_bias {
            raster_desc := _Rasterizer_Desc{
                cull = curr.cull,
                fill = curr.fill,
                depth_bias = curr.depth_bias,
            }
            bucket := &_state.rasterizer_cache[curr.cull][curr.fill]
            raster := bucket_find_or_create(bucket, raster_desc, _create_rasterizer)
            _set_rasterizer(raster)
        }

        if curr.depth_comparison != prev.depth_comparison || curr.depth_write != prev.depth_write || prev.depth_format == .Invalid {
            depth_stencil := &_state.depth_stencil_cache[curr.depth_comparison][curr.depth_write ? 1 : 0]
            if depth_stencil.dss == nil {
                depth_stencil^ = _create_depth_stencil(curr.depth_comparison, curr.depth_write)
            }
            _set_depth_stencil(depth_stencil^)
        }

        if curr.vs != prev.vs {
            if shader, shader_ok := get_internal_shader(curr.vs); shader_ok {
                assert(shader.kind == .Vertex)
                _set_shader(shader^)
            }
        }

        if curr.ps != prev.ps {
            if shader, shader_ok := get_internal_shader(curr.ps); shader_ok {
                assert(shader.kind == .Pixel)
                _set_shader(shader^)
            }
        }

        if curr.resources != prev.resources {
            srvs: [RESOURCE_BIND_SLOTS]^d3d.IShaderResourceView
            for res, i in curr.resources {
                res := get_internal_resource(res) or_continue
                assert(res.srv != nil)
                srvs[i] = res.srv
            }
            _set_resources({.Vertex, .Pixel}, srvs[:], 0)
        }

        if curr.constants != prev.constants {
            cbufs: [CONSTANTS_BIND_SLOTS]^d3d.IBuffer
            for handle, i in curr.constants {
                const := get_internal_resource(handle) or_continue
                cbufs[i] = const.buf
            }
            _set_constants({.Vertex, .Pixel}, cbufs[:], 0)
        }

        if curr.samplers != prev.samplers {
            smps: [SAMPLER_BIND_SLOTS]^d3d.ISamplerState
            for smp, i in curr.samplers {
                bucket := &_state.sampler_cache[smp.filter][smp.bounds.x]
                sampler := bucket_find_or_create(bucket, smp, _create_sampler)
                smps[i] = sampler.smp
            }
            _set_samplers({.Vertex, .Pixel}, smps[:], 0)
        }

        _d3d11_messages()
    }

    _begin_compute_pass :: proc(name: string) {
        // no-op
    }

    _end_compute_pass :: proc() {
        _unbind_cs_rw_resources()
    }

    _bind_compute_pipeline :: proc(
        curr_pip:   Compute_Pipeline_State,
        curr:       Compute_Pipeline_Desc,
        prev:       Compute_Pipeline_Desc,
    ) {
        if curr.cs != prev.cs {
            if shader, shader_ok := get_internal_shader(curr.cs); shader_ok {
                assert(shader.kind == .Compute)
                _set_shader(shader^)
            }
        }

        if curr.resources != prev.resources {
            srvs: [RESOURCE_BIND_SLOTS]^d3d.IShaderResourceView
            for res, i in curr.resources {
                res := get_internal_resource(res) or_continue
                assert(res.srv != nil)
                srvs[i] = res.srv
            }
            _set_resources({.Compute}, srvs[:], 0)
        }

        if curr.rw_resources != prev.rw_resources {
            uavs: [RW_RESOURCE_BIND_SLOTS]^d3d.IUnorderedAccessView
            for res, i in curr.rw_resources {
                res := get_internal_resource(res) or_continue
                assert(res.uav != nil)
                uavs[i] = res.uav
            }
            _set_cs_rw_resources(uavs[:], 0)
        }

        if curr.constants != prev.constants {
            cbufs: [SAMPLER_BIND_SLOTS]^d3d.IBuffer
            for handle, i in curr.constants {
                const := get_internal_resource(handle) or_continue
                cbufs[i] = const.buf
            }
            _set_constants({.Compute}, cbufs[:], 0)
        }

        if curr.samplers != prev.samplers {
            smps: [SAMPLER_BIND_SLOTS]^d3d.ISamplerState
            for smp, i in curr.samplers {
                bucket := &_state.sampler_cache[smp.filter][smp.bounds.x]
                sampler := bucket_find_or_create(bucket, smp, _create_sampler)
                smps[i] = sampler.smp
            }
            _set_samplers({.Compute}, smps[:], 0)
        }

        _d3d11_messages()
    }

    _update_buffer :: proc(res: ^Resource_State, data: []byte, offset: int) {
        switch res.usage {
        case .Immutable:
            assert(false)

        case .Dynamic:
            mapped: d3d.MAPPED_SUBRESOURCE
            if !_d3d11_check(_state.device_context->Map(
                res.buf,
                Subresource = 0,
                MapType = .WRITE_DISCARD,
                MapFlags = {},
                pMappedResource = &mapped,
            )) {
                return
            }

            runtime.mem_copy_non_overlapping(rawptr(uintptr(mapped.pData) + uintptr(offset)), raw_data(data), len(data))

            _state.device_context->Unmap(res.buf, 0)

        case .Default:
            _state.device_context->UpdateSubresource(
                pDstResource = res.buf,
                DstSubresource = 0,
                pDstBox = &d3d.BOX{
                    left    = u32(offset),
                    top     = 0,
                    right   = u32(offset + len(data)),
                    bottom  = 1,
                    front   = 0,
                    back    = 1,
                },
                pSrcData = raw_data(data),
                SrcRowPitch = 0,
                SrcDepthPitch = 0,
            )
        }

        _d3d11_messages()
    }

    _update_constants :: proc(res: ^Resource_State, data: []byte) {
        if res.size.y > 1 {
            // This is a multi constant buffer, delay updates based on dynamic offsets.
            // The actual buffer will be set dynamically when drawing. Should be
            // fast thanks to internal D3D11 driver buffer renaming.

            err: runtime.Allocator_Error
            res.const_buf_data, err = runtime.mem_alloc_non_zeroed(len(data), 256, context.temp_allocator)
            assert(err == nil)
            runtime.mem_copy_non_overlapping(raw_data(res.const_buf_data), raw_data(data), len(data))

        } else {
            mapped: d3d.MAPPED_SUBRESOURCE
            if !_d3d11_check(_state.device_context->Map(
                res.buf,
                Subresource = 0,
                MapType = .WRITE_DISCARD,
                MapFlags = {},
                pMappedResource = &mapped,
            )) {
                return
            }

            runtime.mem_copy_non_overlapping(mapped.pData, raw_data(data), len(data))

            _state.device_context->Unmap(res.buf, 0)
        }
    }

    _map_buffer :: proc(res: _Resource) -> [^]byte {
        mapped: d3d.MAPPED_SUBRESOURCE
        if !_d3d11_check(_state.device_context->Map(
            res.buf,
            Subresource = 0,
            MapType = .WRITE_DISCARD,
            MapFlags = {},
            pMappedResource = &mapped,
        )) {
            return {}
        }

        _d3d11_messages()

        return (cast([^]byte)mapped.pData)
    }

    _unmap_buffer :: proc(res: _Resource) {
        _state.device_context->Unmap(res.buf, 0)

        _d3d11_messages()
    }

    _update_texture_2d :: proc(res: Resource_State, data: []byte, slice: i32) {
        sub := _d3d11_calc_subresource(0, slice, 1)

        _state.device_context->UpdateSubresource(
            pDstResource = res.tex2d,
            DstSubresource = sub,
            pDstBox = nil,
            pSrcData = raw_data(data),
            SrcRowPitch = u32(res.size.x * texture_pixel_size(res.format)),
            SrcDepthPitch = 0,
        )

        _d3d11_messages()
    }

    _clear_render_texture :: proc(tex: _Resource, color: [4]f32) {
        color := color
        assert(tex.rtv != nil)
        _state.device_context->ClearRenderTargetView(tex.rtv, &color)

        _d3d11_messages()
    }

    _clear_depth_texture :: proc(tex: _Resource, value: f32) {
        assert(tex.dsv != nil)
        _state.device_context->ClearDepthStencilView(tex.dsv, {.DEPTH}, Depth = value, Stencil = 0)

        _d3d11_messages()
    }

    _update_draw_constants :: proc(const_offsets: []u32) {
        // TODO: some of this should be cached on bind_pipeline
        for offset, i in const_offsets {
            if offset == max(u32) {
                continue
            }

            handle := _state.curr_pipeline_desc.constants[i]

            res := get_internal_resource(handle) or_continue

            assert(res.kind == .Constants)

            if res.size.y == 1 {
                continue
            }

            assert(res.const_buf_data != nil)

            data := &res.const_buf_data[int(offset) * int(res.size.x)]

            mapped: d3d.MAPPED_SUBRESOURCE
            if !_d3d11_check(_state.device_context->Map(
                res.buf,
                Subresource = 0,
                MapType = .WRITE_DISCARD,
                MapFlags = {},
                pMappedResource = &mapped,
            )) {
                return
            }

            runtime.mem_copy_non_overlapping(mapped.pData, data, int(res.size.x))

            _state.device_context->Unmap(res.buf, 0)
        }
    }

    _draw_non_indexed :: proc(
        vertex_num:     u32,
        instance_num:   u32,
        const_offsets:  []u32,
    ) {
        _update_draw_constants(const_offsets)

        _state.device_context->DrawInstanced(
            VertexCountPerInstance = vertex_num,
            InstanceCount = instance_num,
            StartVertexLocation = 0,
            StartInstanceLocation = 0,
        )

        _d3d11_messages()
    }

    _draw_indexed :: proc(
        index_num:      u32,
        instance_num:   u32,
        index_offset:   u32,
        const_offsets:  []u32,
    ) {
        _update_draw_constants(const_offsets)

        _state.device_context->DrawIndexedInstanced(
            IndexCountPerInstance = index_num,
            InstanceCount = instance_num,
            StartIndexLocation = index_offset,
            BaseVertexLocation = 0, // NOTE: not supported since vertex buffers must be structured buffers
            StartInstanceLocation = 0,
        )

        _d3d11_messages()
    }


    _dispatch_compute :: proc(size: [3]i32) {
        _state.device_context->Dispatch(
            ThreadGroupCountX = u32(size.x),
            ThreadGroupCountY = u32(size.y),
            ThreadGroupCountZ = u32(size.z),
        )

        _d3d11_messages()
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: d3d11 utils
    //


    _d3d11_setlabel :: proc(self: ^d3d.IDeviceChild, label: string) {
        buf: [128]u16
        wstr := windows.utf8_to_utf16_buf(buf[:], label)
        self->SetPrivateData(d3d.WKPDID_D3DDebugObjectNameW_UUID, u32(size_of(u16) * len(wstr)), raw_data(wstr))
    }

    _d3d11_calc_subresource :: proc(mip: i32, slice: i32, mip_levels: i32) -> u32 {
        return u32(mip + (slice * mip_levels))
    }

    @(private = "file")
    _d3d11_check :: proc(res: dxgi.HRESULT, loc := #caller_location) -> bool {
        // TODO: #caller_expression

        switch cast(u32)res {
        case 0:
            return true
        case 1:
            base.log_warn("GPU D3D11: S_FALSE: Successful but nonstandard completion (the precise meaning depends on context).", loc = loc)
            return true

        case 0x887C0002:
            base.log_err("GPU D3D11: D3D11_ERROR_FILE_NOT_FOUND: The file was not found.", loc = loc)
        case 0x887C0001:
            base.log_err("GPU D3D11: D3D11_ERROR_TOO_MANY_UNIQUE_STATE_OBJECTS: There are too many unique instances of a particular type of state object.", loc = loc)
        case 0x887C0003:
            base.log_err("GPU D3D11: D3D11_ERROR_TOO_MANY_UNIQUE_VIEW_OBJECTS: There are too many unique instances of a particular type of view object.", loc = loc)
        case 0x887C0004:
            base.log_err("GPU D3D11: D3D11_ERROR_DEFERRED_CONTEXT_MAP_WITHOUT_INITIAL_DISCARD: The first call to ID3D11DeviceContext::Map after either ID3D11Device::CreateDeferredContext or ID3D11DeviceContext::FinishCommandList per Resource was not D3D11_MAP_WRITE_DISCARD.", loc = loc)
        case 0x887A0001:
            base.log_err("GPU D3D11: DXGI_ERROR_INVALID_CALL: The method call is invalid. For example, a method's parameter may not be a valid pointer.", loc = loc)
        case 0x887A000A:
            base.log_err("GPU D3D11: DXGI_ERROR_WAS_STILL_DRAWING: The previous blit operation that is transferring information to or from this surface is incomplete.", loc = loc)
        case 0x887A002D:
            base.log_err("GPU D3D11: DXGI_ERROR_SDK_COMPONENT_MISSING: An SDK component is missing or mismatched.", loc = loc)
        case 0x80004005:
            base.log_err("GPU D3D11: E_FAIL: Attempted to create a device with the debug layer enabled and the layer is not installed.", loc = loc)
        case 0x80070057:
            base.log_err("GPU D3D11: E_INVALIDARG: An invalid parameter was passed to the returning function.", loc = loc)
        case 0x8007000E:
            base.log_err("GPU D3D11: E_OUTOFMEMORY: Direct3D could not allocate sufficient memory to complete the call.", loc = loc)
        case 0x80004001:
            base.log_err("GPU D3D11: E_NOTIMPL: The method call isn't implemented with the passed parameter combination.", loc = loc)
        }

        _d3d11_messages()

        if VALIDATION {
            panic("GPU D3D11: Error Result", loc = loc)
        }

        return false
    }

    @(disabled = RELEASE)
    _d3d11_messages :: proc(loc := #caller_location) {
        when !RELEASE {
            defer _state.info_queue->ClearStoredMessages()

            buf: [1024]u8

            count := _state.info_queue->GetNumStoredMessages()
            for i in 0..<count {
                msg_size: uint
                _state.info_queue->GetMessage(i, nil, &msg_size)

                msg := cast(^d3d.MESSAGE)make_multi_pointer([^]byte, msg_size, context.temp_allocator)
                _state.info_queue->GetMessage(i, msg, &msg_size)

                level: base.Log_Level
                switch msg.Severity {
                case .CORRUPTION: level = .Fatal
                case .ERROR: level = .Error
                case .WARNING: level = .Warning
                case .INFO: level = .Info
                case .MESSAGE: level = .Debug
                }

                base.log(level, "GPU D3D11 %v: %v", msg.Category, msg.pDescription, loc = loc)

                if msg.Severity == .CORRUPTION || msg.Severity == .ERROR {
                    panic("GPU D3D11: Error")
                }

                if VALIDATION && msg.Severity == .WARNING {
                    panic("GPU D3D11: Warning")
                }
            }
        }
    }

    _d3d11_usage :: proc(usage: Usage) -> d3d.USAGE {
        switch usage {
        case .Default:   return .DEFAULT
        case .Immutable: return .IMMUTABLE
        case .Dynamic:   return .DYNAMIC
        }
        assert(false)
        return .DEFAULT
    }

    _d3d11_blend_op :: proc(blend_op: Blend_Op) -> d3d.BLEND_OP {
        switch blend_op {
            case .Add: return .ADD
            case .Sub: return .SUBTRACT
            case .Reverse_Sub: return .REV_SUBTRACT
            case .Min: return .MIN
            case .Max: return .MAX
        }
        assert(false)
        return .ADD
    }

    _d3d11_blend_factor :: proc(blend_factor: Blend_Factor) -> d3d.BLEND {
        switch blend_factor {
        case .Zero:                 return .ZERO
        case .One:                  return .ONE
        case .Src_Color:            return .SRC_COLOR
        case .One_Minus_Src_Color:  return .INV_SRC_COLOR
        case .Src_Alpha:            return .SRC_ALPHA
        case .One_Minus_Src_Alpha:  return .INV_SRC_ALPHA
        case .Dst_Alpha:            return .DEST_ALPHA
        case .One_Minus_Dst_Alpha:  return .INV_DEST_ALPHA
        case .Dst_Color:            return .DEST_COLOR
        case .One_Minus_Dst_Color:  return .INV_DEST_COLOR
        case .Src_Alpha_Sat:        return .SRC_ALPHA_SAT
        }
        assert(false)
        return .ONE
    }

    _d3d11_cpu_access :: proc(usage: Usage) -> d3d.CPU_ACCESS_FLAGS {
        switch usage {
        case .Dynamic:
            return {.WRITE}
        case .Immutable, .Default:
            return {}
        }
        assert(false)
        return {}
    }

    _d3d11_index_format :: proc(format: Index_Format) -> dxgi.FORMAT {
        switch format {
        case .Invalid:  return .UNKNOWN
        case .U16: return .R16_UINT
        case .U32: return .R32_UINT
        }
        assert(false)
        return .R32_UINT
    }

    _d3d11_texture_bounds :: proc(bounds: Texture_Bounds) -> d3d.TEXTURE_ADDRESS_MODE {
        switch bounds {
        case .Wrap:         return .WRAP
        case .Mirror:       return .MIRROR
        case .Clamp:        return .CLAMP
        }
        assert(false)
        return .WRAP
    }


    _d3d11_topology :: proc(topology: Topology) -> d3d.PRIMITIVE_TOPOLOGY {
        switch topology {
        case .Invalid:      return .TRIANGLELIST
        case .Lines:        return .LINELIST
        case .Triangles:    return .TRIANGLELIST
        }
        assert(false)
        return .TRIANGLELIST
    }

    _d3d11_fill_mode :: proc(fill_mode: Fill_Mode) -> d3d.FILL_MODE {
        switch fill_mode {
        case .Invalid:      return .SOLID
        case .Solid:        return .SOLID
        case .Wireframe:    return .WIREFRAME
        }
        assert(false)
        return .SOLID
    }

    _d3d11_cull_mode :: proc(cull_mode: Cull_Mode) -> d3d.CULL_MODE {
        switch cull_mode {
        case .Invalid:  return .NONE
        case .None:     return .NONE
        case .Front:    return .FRONT
        case .Back:    return .BACK
        }
        assert(false)
        return .NONE
    }

    _d3d11_depth_write :: proc(depth_write: bool) -> d3d.DEPTH_WRITE_MASK {
        if depth_write {
            return .ALL
        } else {
            return .ZERO
        }
        assert(false)
        return .ALL
    }

    _d3d11_comparison :: proc(op: Comparison_Op) -> d3d.COMPARISON_FUNC {
        switch op {
        case .Never:         return .NEVER
        case .Less:          return .LESS
        case .Equal:         return .EQUAL
        case .Less_Equal:    return .LESS_EQUAL
        case .Greater:       return .GREATER
        case .Not_Equal:     return .NOT_EQUAL
        case .Greater_Equal: return .GREATER_EQUAL
        case .Always:        return .ALWAYS
        }
        assert(false)
        return .ALWAYS
    }

    _d3d11_filter :: proc(filter: Filter) -> d3d.FILTER {
        switch filter {
        case .Unfiltered:       return .MIN_MAG_MIP_POINT
        case .Mip_Filtered:     return .MIN_MAG_POINT_MIP_LINEAR
        case .Mag_Filtered:     return .MIN_POINT_MAG_LINEAR_MIP_POINT
        case .Mag_Mip_Filtered: return .MIN_POINT_MAG_MIP_LINEAR
        case .Min_Filtered:     return .MIN_LINEAR_MAG_MIP_POINT
        case .Min_Mip_Filtered: return .MIN_LINEAR_MAG_POINT_MIP_LINEAR
        case .Min_Mag_Filtered: return .MIN_MAG_LINEAR_MIP_POINT
        case .Filtered:         return .MIN_MAG_MIP_LINEAR
        }
        assert(false)
        return .MIN_MAG_MIP_POINT
    }

    _d3d11_texture_format :: proc(format: Texture_Format) -> dxgi.FORMAT {
        switch format {
        case .Invalid:          return .UNKNOWN
        case .RGBA_F32:         return .R32G32B32A32_FLOAT
        case .RGBA_U32:         return .R32G32B32A32_UINT
        case .RGBA_S32:         return .R32G32B32A32_SINT
        case .RGBA_F16:         return .R16G16B16A16_FLOAT
        case .RGBA_U16_Norm:    return .R16G16B16A16_UNORM
        case .RGBA_U16:         return .R16G16B16A16_UINT
        case .RGBA_S16_Norm:    return .R16G16B16A16_SNORM
        case .RGBA_S16:         return .R16G16B16A16_SINT
        case .RG_F32:           return .R32G32_FLOAT
        case .RG_U32:           return .R32G32_UINT
        case .RG_S32:           return .R32G32_SINT
        case .RG_U10_A_U2_Norm: return .R10G10B10A2_UNORM
        case .RG_U10_A_U2:      return .R10G10B10A2_UINT
        case .RG_F11_B_F10:     return .R11G11B10_FLOAT
        case .RGBA_U8_Norm:     return .R8G8B8A8_UNORM
        case .RGBA_U8:          return .R8G8B8A8_UINT
        case .RGBA_S8_Norm:     return .R8G8B8A8_SNORM
        case .RGBA_S8:          return .R8G8B8A8_SINT
        case .RG_F16:           return .R16G16_FLOAT
        case .RG_U16_Norm:      return .R16G16_UNORM
        case .RG_U16:           return .R16G16_UINT
        case .RG_S16_Norm:      return .R16G16_SNORM
        case .RG_S16:           return .R16G16_SINT
        case .D_F32:            return .D32_FLOAT
        case .R_F32:            return .R32_FLOAT
        case .R_U32:            return .R32_UINT
        case .R_S32:            return .R32_SINT
        case .D_U24_Norm_S_U8:  return .D24_UNORM_S8_UINT
        case .RG_U8_Norm:       return .R8G8_UNORM
        case .RG_U8:            return .R8G8_UINT
        case .RG_S8_Norm:       return .R8G8_SNORM
        case .RG_S8:            return .R8G8_SINT
        case .R_F16:            return .R16_FLOAT
        case .D_U16_Norm:       return .D16_UNORM
        case .R_U16_Norm:       return .R16_UNORM
        case .R_U16:            return .R16_UINT
        case .R_S16_Norm:       return .R16_SNORM
        case .R_S16:            return .R16_SINT
        case .R_U8_Norm:        return .R8_UNORM
        case .R_U8:             return .R8_UINT
        case .R_S8_Norm:        return .R8_SNORM
        case .R_S8:             return .R8_SINT
        }
        assert(false)
        return .R8G8B8A8_UNORM
    }

}