#+vet explicit-allocators style shadowing unused
#+build windows
package ravn_gpu

import "../base"
import "base:runtime"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

_ :: base
_ :: runtime
_ :: windows
_ :: d3d11
_ :: dxgi

// https://www.gamedevs.org/uploads/efficient-buffer-management.pdf
// TODO: all input constraints must be spelled out at the top if each proc in gpu.odin.

when BACKEND == BACKEND_D3D11 {

    _SAMPLER_CACHE_BUCKET :: 8
    _RASTERIZER_CACHE_BUCKET :: 8
    _BLEND_CACHE_BUCKET :: 32
    _MAX_DEPTH_STENCILS :: 8
    _MAX_SAMPLERS :: 32
    _MAX_RASTERIZERS :: 32
    _MAX_BLENDS :: 32
    _MAX_INPUT_LAYOUTS :: 32

    _State :: struct {
        device:                 ^d3d11.IDevice,
        device_context:         ^ID3D11DeviceContext1,
        dxgi_factory:           ^dxgi.IFactory2,
        swapchain:              ^dxgi.ISwapChain1,
        swapchain_tex:          ^d3d11.ITexture2D,
        swapchain_rtv:          ^d3d11.IRenderTargetView,
        render_texture:         ^d3d11.ITexture2D,
        render_texture_view:    ^d3d11.IRenderTargetView,
        info_queue:             ^d3d11.IInfoQueue,

        prev_graphics_pip:      Graphics_Pipeline_State,
        prev_compute_pip:       Compute_Pipeline_State,
        depth_stencils:         [dynamic; _MAX_DEPTH_STENCILS]_Depth_Stencil_State,
        samplers:               [dynamic; _MAX_SAMPLERS]_Sampler_State,
        rasterizers:            [dynamic; _MAX_RASTERIZERS]_Rasterizer_State,
        blends:                 [dynamic; _MAX_BLENDS]_Blend_State,
        input_layouts:          [dynamic; _MAX_INPUT_LAYOUTS]_Input_Layout_State,
    }

    _Graphics_Pipeline_State :: struct #all_or_none {
        blend:          ^d3d11.IBlendState,
        rasterizer:     ^d3d11.IRasterizerState,
        depth_stencil:  ^d3d11.IDepthStencilState,
        input_layout:   ^d3d11.IInputLayout,
    }

    _Compute_Pipeline_State :: struct #all_or_none {

    }

    _Sampler_State :: struct #all_or_none {
        smp:    ^d3d11.ISamplerState,
        desc:   Sampler_Desc,
    }

    _Depth_Stencil_State :: struct #all_or_none {
        dss:    ^d3d11.IDepthStencilState,
        desc:   _Depth_Stencil_Desc,
    }

    _Blend_State :: struct #all_or_none {
        bs:     ^d3d11.IBlendState,
        descs:  [MAX_BOUND_RENDER_TEXTURES]Blend_Desc,
    }

    _Rasterizer_State :: struct #all_or_none {
        rs:     ^d3d11.IRasterizerState,
        desc:   _Rasterizer_Desc,
    }

    _Rasterizer_Desc :: struct #all_or_none {
        cull:       Cull_Mode,
        fill:       Fill_Mode,
        depth_bias: i32,
    }

    _Depth_Stencil_Desc :: struct #all_or_none {
        comparison: Comparison_Op,
        write:      bool,
    }

    _Resource_State :: struct #all_or_none {
        srv:    ^d3d11.IShaderResourceView,
        uav:    ^d3d11.IUnorderedAccessView,
        using _: struct #raw_union {
            res:    ^d3d11.IResource, // shared
            using _: struct {
                tex2d:  ^d3d11.ITexture2D,
                rtv:    ^d3d11.IRenderTargetView,
                dsv:    ^d3d11.IDepthStencilView,
            },
            tex3d:  ^d3d11.ITexture3D,
            using _: struct {
                buf:    ^d3d11.IBuffer,
                const_buf_data: []byte,
            },
        },
    }

    _Shader_State :: struct #all_or_none {
        using _: struct #raw_union {
            vs: ^d3d11.IVertexShader,
            ps: ^d3d11.IPixelShader,
            cs: ^d3d11.IComputeShader,
        },
    }

    _Constants_State :: struct #all_or_none {
        cbuf:   ^d3d11.IBuffer,
    }

    _Bind_Layout_State :: struct #all_or_none {

    }

    _Bind_Group_State :: struct #all_or_none {
        smps:           [dynamic; MAX_BIND_GROUP_SAMPLERS]^d3d11.ISamplerState,
        cbufs:          [dynamic; MAX_BIND_GROUP_CONSTANTS]^d3d11.IBuffer,
        srvs:           [dynamic; MAX_BIND_GROUP_RESOURCES]^d3d11.IShaderResourceView,
        uavs:           [dynamic; MAX_BIND_GROUP_RW_RESOURCES]^d3d11.IUnorderedAccessView,
        smp_stages:     bit_set[Shader_Kind],
        cbuf_stages:    bit_set[Shader_Kind],
        srv_stages:     bit_set[Shader_Kind],
    }

    _Input_Layout_State :: struct #all_or_none {
        il:     ^d3d11.IInputLayout,
        desc:   _Input_Layout_Desc,
    }

    _Input_Layout_Desc :: struct #all_or_none {
        vertex_layouts:     [MAX_PIPELINE_VERTEX_LAYOUTS]Vertex_Layout_Desc,
        vs_handle:          Shader_Handle,
    }

    _init :: proc(native_window: rawptr) -> bool {
        base_device: ^d3d11.IDevice
        base_device_context: ^d3d11.IDeviceContext

        feature_levels := [?]d3d11.FEATURE_LEVEL{._11_1}
        device_flags: d3d11.CREATE_DEVICE_FLAGS = {
            .SINGLETHREADED,
            .BGRA_SUPPORT,
        }

        if !RELEASE {
            device_flags += {.DEBUG}
        }

        id := base.create_debug_id("D3D11Init", allocator = context.temp_allocator)

        if !_d3d11_check(id, d3d11.CreateDevice(
            pAdapter = nil,
            DriverType = .HARDWARE,
            Software = nil,
            Flags = device_flags,
            pFeatureLevels = &feature_levels[0],
            FeatureLevels = len(feature_levels),
            SDKVersion = d3d11.SDK_VERSION,
            ppDevice = &base_device,
            pFeatureLevel = nil,
            ppImmediateContext = &base_device_context,
        )) {
            base.log_err("Failed to create D3D11 device")
            return false
        }

        _d3d11_check(id, base_device->QueryInterface(d3d11.IDevice_UUID, cast(^rawptr)&_state.device)) or_return
        // _d3d11_check(id, base_device_context->QueryInterface(d3d11.IDeviceContext_UUID, cast(^rawptr)&_state.device_context)) or_return
        _d3d11_check(id, base_device_context->QueryInterface(ID3D11DeviceContext1_UUID, cast(^rawptr)&_state.device_context)) or_return

        dxgi_device: ^dxgi.IDevice1
        _d3d11_check(id, _state.device->QueryInterface(dxgi.IDevice1_UUID, cast(^rawptr)&dxgi_device)) or_return

        dxgi_adapter: ^dxgi.IAdapter
        _d3d11_check(id, dxgi_device->GetAdapter(&dxgi_adapter)) or_return

        _d3d11_check(id, dxgi_adapter->GetParent(dxgi.IFactory2_UUID, cast(^rawptr)&_state.dxgi_factory)) or_return

        // TODO: investigate more
        _d3d11_check(id, dxgi_device->SetMaximumFrameLatency(1)) or_return

        if !RELEASE {
            _d3d11_check(id, _state.device->QueryInterface(d3d11.IInfoQueue_UUID, cast(^rawptr)&_state.info_queue)) or_return
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
        _state.device_context->IASetIndexBuffer(nil, .R32_UINT, 0)
        _d3d11_messages()
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

    _create_graphics_pipeline :: proc(id: base.Debug_ID, desc: Graphics_Pipeline_Desc) -> (result: _Graphics_Pipeline_State, ok: bool) {
        result.blend = _getref_or_create_blend(id, desc.blends).bs
        result.depth_stencil = _getref_or_create_depth_stencil(id, _Depth_Stencil_Desc{
            comparison = desc.depth_comparison,
            write = desc.depth_write,
        }).dss
        result.rasterizer = _getref_or_create_rasterizer(id, _Rasterizer_Desc{
            cull = desc.cull,
            fill = desc.fill,
            depth_bias = desc.depth_bias,
        }).rs
        result.input_layout = _getref_or_create_input_layout(id, _Input_Layout_Desc{
            vertex_layouts = desc.vertex_layouts,
            vs_handle = desc.vs,
        }).il
        return result, true
    }

    _create_compute_pipeline :: proc(id: base.Debug_ID, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline_State, ok: bool) {
        return {}, true
    }

    _create_bind_layout :: proc(id: base.Debug_ID, desc: Bind_Layout_Desc) -> (result: _Bind_Layout_State, ok: bool) {
        return {}, true
    }

    _create_bind_group :: proc(id: base.Debug_ID, desc: Bind_Group_Desc) -> (result: _Bind_Group_State, ok: bool) {
        layout, layout_ok := _get_bind_layout(desc.layout)
        assert(layout_ok)

        for slot in layout.desc.slots {
            switch slot.kind {
            case .Sampler:
                result.smp_stages += slot.stages

            case .Constants, .Constants_Dynamic:
                result.cbuf_stages += slot.stages

            case .Resource_Buffer,
                 .Resource_Texture_2D,
                 .Resource_Texture_2D_Array,
                 .Resource_Texture_3D:
                result.srv_stages += slot.stages

            case .RW_Resource_Buffer,
                 .RW_Resource_Texture_2D,
                 .RW_Resource_Texture_2D_Array,
                 .RW_Resource_Texture_3D:
                // UAV stages ignored, compute only
            }
        }

        for slot, i in desc.slots {
            if slot.resource != {} {
                assert(slot.sampler == {})

                res, res_ok := _get_resource(slot.resource)
                assert(res_ok)

                switch res.kind {
                case .Invalid:
                    assert(false)

                case .Constants:
                    assert(res.buf != nil)
                    resize(&result.cbufs, slot.index + 1)
                    result.cbufs[slot.index] = res.buf

                case .Buffer:
                    assert(res.srv != nil)
                    resize(&result.srvs, slot.index + 1)
                    result.srvs[slot.index] = res.srv

                case .Texture2D, .Texture3D:
                    if _is_bind_layout_slot_rw(layout.desc.slots[i].kind) {
                        assert(res.uav != nil)
                        resize(&result.uavs, slot.index + 1)
                        result.uavs[slot.index] = res.uav
                    } else {
                        assert(res.srv != nil)
                        resize(&result.srvs, slot.index + 1)
                        result.srvs[slot.index] = res.srv
                    }
                }

            } else {
                assert(slot.sampler != {})
                resize(&result.smps, slot.index + 1)
                result.smps[slot.index] = _getref_or_create_sampler(id, slot.sampler).smp
            }
        }

        return result, true
    }

    _getref_or_create_input_layout :: proc(id: base.Debug_ID, desc: _Input_Layout_Desc) -> (result: _Input_Layout_State) {
        if desc.vertex_layouts == {} {
            return {}
        }

        for existing in _state.input_layouts {
            if existing != {} && existing.desc == desc {
                assert(existing.il != nil)
                existing.il->AddRef()
                return existing
            }
        }

        base.log_debug("GPU: Creating D3D11 input layout")

        vs, vs_ok := _get_shader(desc.vs_handle)
        if !vs_ok {
            assert(false)
            return {}
        }

        num_elems := 0
        elems: [MAX_VERTEX_LAYOUT_SLOTS * MAX_PIPELINE_VERTEX_LAYOUTS]d3d11.INPUT_ELEMENT_DESC

        for layout, layout_index in desc.vertex_layouts {
            if layout == {} {
                continue
            }

            offset := 0
            for format in layout.slots {
                if format == {} {
                    break
                }
                elem := d3d11.INPUT_ELEMENT_DESC{
                    SemanticName = "TEXCOORD",
                    SemanticIndex = u32(num_elems),
                    Format = _d3d11_vertex_format(format),
                    InputSlot = u32(layout_index),
                    AlignedByteOffset = u32(offset),
                    InputSlotClass = layout.mode == .Instance ? .INSTANCE_DATA : .VERTEX_DATA,
                    InstanceDataStepRate = layout.mode == .Instance ? 1 : 0,
                }

                elems[num_elems] = elem
                offset += get_vertex_format_size(format)
                offset = runtime.align_forward_int(offset, 4)
                num_elems += 1
            }
        }

        _d3d11_check(id, _state.device->CreateInputLayout(
            pInputElementDescs = &elems[0],
            NumElements = u32(num_elems),
            pShaderBytecodeWithInputSignature = raw_data(vs.data),
            BytecodeLength = uint(len(vs.data)),
            ppInputLayout = &result.il,
        ));

        result.desc = desc
        append(&_state.input_layouts, result)

        _d3d11_messages()
        return result
    }

    _getref_or_create_rasterizer :: proc(id: base.Debug_ID, desc: _Rasterizer_Desc) -> (result: _Rasterizer_State) {
        for existing in _state.rasterizers {
            if existing != {} && existing.desc == desc {
                assert(existing.rs != nil)
                existing.rs->AddRef()
                return existing
            }
        }

        base.log_debug("GPU: Creating D3D11 rasterizer")

        rasterizer_desc := d3d11.RASTERIZER_DESC{
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
        _d3d11_check(id, _state.device->CreateRasterizerState(&rasterizer_desc, &result.rs))

        result.desc = desc
        append(&_state.rasterizers, result)

        _d3d11_messages()
        return result
    }

    _getref_or_create_depth_stencil :: proc(id: base.Debug_ID, desc: _Depth_Stencil_Desc) -> (result: _Depth_Stencil_State) {
        for existing in _state.depth_stencils {
            if existing != {} && existing.desc == desc {
                assert(existing.dss != nil)
                existing.dss->AddRef()
                return existing
            }
        }

        base.log_debug("GPU: Creating D3D11 depth stencil")

        result.desc = desc
        depth_stencil_desc := d3d11.DEPTH_STENCIL_DESC{
            DepthEnable         = d3d11.BOOL(_depth_enable(desc.comparison, desc.write)),
            DepthWriteMask      = _d3d11_depth_write(desc.write),
            DepthFunc           = _d3d11_comparison(desc.comparison),
            StencilEnable       = false,
            StencilReadMask     = d3d11.DEFAULT_STENCIL_READ_MASK,
            StencilWriteMask    = d3d11.DEFAULT_STENCIL_WRITE_MASK,
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
        _d3d11_check(id, _state.device->CreateDepthStencilState(&depth_stencil_desc, &result.dss))

        result.desc = desc
        append(&_state.depth_stencils, result)

        _d3d11_messages()
        return result
    }

    _getref_or_create_sampler :: proc(id: base.Debug_ID, desc: Sampler_Desc) -> (result: _Sampler_State) {
        for existing in _state.samplers {
            if existing != {} && existing.desc == desc {
                assert(existing.smp != nil)
                existing.smp->AddRef()
                return existing
            }
        }

        base.log_debug("GPU: Creating D3D11 sampler")

        _d3d11_check(id, _state.device->CreateSamplerState(&d3d11.SAMPLER_DESC{
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
        }, &result.smp))

        result.desc = desc
        append(&_state.samplers, result)

        _d3d11_messages()
        return result
    }

    _getref_or_create_blend :: proc(id: base.Debug_ID, descs: [MAX_BOUND_RENDER_TEXTURES]Blend_Desc) -> (result: _Blend_State) {
        if descs == {} {
            return {}
        }

        for existing in _state.blends {
            if existing.descs == descs {
                assert(existing.bs != nil)
                existing.bs->AddRef()
                return existing
            }
        }

        base.log_debug("GPU: Creating D3D11 blend state")

        blend_desc := d3d11.BLEND_DESC{
            AlphaToCoverageEnable = false,
            IndependentBlendEnable = true,
        }

        for desc, i in descs {
            blend_desc.RenderTarget[i] = _d3d11_blend_desc(desc)
        }

        _d3d11_check(id, _state.device->CreateBlendState(&blend_desc, &result.bs))

        result.descs = descs
        append(&_state.blends, result)

        _d3d11_messages()
        return result

        _d3d11_blend_desc :: proc(desc: Blend_Desc) -> d3d11.RENDER_TARGET_BLEND_DESC {
            if desc == {} {
                return d3d11.RENDER_TARGET_BLEND_DESC{BlendEnable = false}
            }
            return d3d11.RENDER_TARGET_BLEND_DESC{
                BlendEnable             = true,
                SrcBlend                = _d3d11_blend_factor(desc.src_color),
                DestBlend               = _d3d11_blend_factor(desc.dst_color),
                BlendOp                 = _d3d11_blend_op(desc.op_color),
                SrcBlendAlpha           = _d3d11_blend_factor(desc.src_alpha),
                DestBlendAlpha          = _d3d11_blend_factor(desc.dst_alpha),
                BlendOpAlpha            = _d3d11_blend_op(desc.op_alpha),
                RenderTargetWriteMask   = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
            },
        }
    }

    _resize_swapchain :: proc(window: rawptr, size: [2]i32) -> (ok: bool) {
        assert(window != nil)
        assert(size.x > 0)
        assert(size.y > 0)
        assert(_state.device != nil)
        assert(_state.device_context != nil)

        id := base.create_debug_id("D3D11Swapchain", allocator = context.temp_allocator)

        if _state.swapchain == nil {
            swapchain_desc := dxgi.SWAP_CHAIN_DESC1{
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

            _d3d11_check(id, _state.dxgi_factory->CreateSwapChainForHwnd(
                _state.device, dxgi.HWND(window), &swapchain_desc, nil, nil, &_state.swapchain,
            )) or_return

        } else {
            assert(_state.swapchain_tex != nil)
            assert(_state.swapchain_rtv != nil)

            _state.device_context->OMSetRenderTargets(0, nil, nil)
            _state.device_context->Flush()
            _state.swapchain_tex->Release()
            _state.swapchain_rtv->Release()

            _d3d11_check(id, _state.swapchain->ResizeBuffers(
                BufferCount = 0,
                Width  = u32(size.x),
                Height = u32(size.y),
                NewFormat = .UNKNOWN,
                SwapChainFlags = {},
            )) or_return
        }

        _d3d11_messages()

        _d3d11_check(id, _state.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&_state.swapchain_tex)) or_return
        _d3d11_check(id, _state.device->CreateRenderTargetView(_state.swapchain_tex, nil, &_state.swapchain_rtv)) or_return
        _d3d11_setlabel(_state.swapchain_tex, "Swapchain")

        _state.device_context->RSSetViewports(1, &d3d11.VIEWPORT{
            Width  = f32(size.x),
            Height = f32(size.y),
            MinDepth = 0,
            MaxDepth = 1,
        })

        _d3d11_messages()

        return true
    }

    // data: DXBC bytecode
    _create_shader :: proc(id: base.Debug_ID, data: []u8, kind: Shader_Kind) -> (result: _Shader_State, ok: bool) {
        switch kind {
        case .Invalid:
            assert(false)

        case .Vertex:
            _d3d11_check(id, _state.device->CreateVertexShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppVertexShader = &result.vs,
            )) or_return

            _d3d11_setlabel(result.vs, base.get_debug_id_name(id))

        case .Pixel:
            _d3d11_check(id, _state.device->CreatePixelShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppPixelShader = &result.ps,
            )) or_return

            _d3d11_setlabel(result.ps, base.get_debug_id_name(id))

        case .Compute:
            _d3d11_check(id, _state.device->CreateComputeShader(
                pShaderBytecode = raw_data(data),
                BytecodeLength = uint(len(data)),
                pClassLinkage = nil,
                ppComputeShader = &result.cs,
            )) or_return

            _d3d11_setlabel(result.cs, base.get_debug_id_name(id))
        }

        _d3d11_messages()

        return result, true
    }

    _create_buffer :: proc(
        id:     base.Debug_ID,
        kind:   Buffer_Kind,
        size:   i32,
        stride: i32,
        usage:  Usage,
        data:   []u8,
    ) -> (result: _Resource_State, ok: bool) {
        bind_flags: d3d11.BIND_FLAGS
        switch kind {
        case .Invalid:
            assert(false)
        case .Storage:
            bind_flags += {.SHADER_RESOURCE}
        case .Vertex:
            bind_flags += {.VERTEX_BUFFER}
        case .Index:
            bind_flags += {.INDEX_BUFFER}
        }

        desc := d3d11.BUFFER_DESC{
            ByteWidth           = u32(size),
            StructureByteStride = kind == .Storage ? u32(stride) : 0,
            Usage               = _d3d11_usage(usage),
            BindFlags           = bind_flags,
            CPUAccessFlags      = _d3d11_cpu_access(usage),
            MiscFlags           = kind == .Storage ? {.BUFFER_STRUCTURED} : {},
        }

        initial_data := d3d11.SUBRESOURCE_DATA{
            pSysMem = raw_data(data),
        }

        initial_data_ptr: ^d3d11.SUBRESOURCE_DATA
        if data != nil {
            initial_data_ptr = &initial_data
        }

        _d3d11_check(id, _state.device->CreateBuffer(&desc, initial_data_ptr, &result.buf)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.buf, base.get_debug_id_name(id))

        if kind == .Storage {
            _d3d11_check(id, _state.device->CreateShaderResourceView(result.buf, nil, &result.srv)) or_return
            _d3d11_messages()
            _d3d11_setlabel(result.srv, base.get_debug_id_name(id))
        }

        return result, true
    }

    _create_constants :: proc(id: base.Debug_ID, item_size: i32, item_num: i32) -> (result: _Resource_State, ok: bool) {
        desc := d3d11.BUFFER_DESC{
            ByteWidth = u32(item_size * item_num),
            Usage = .DYNAMIC,
            BindFlags = {.CONSTANT_BUFFER},
            CPUAccessFlags = {.WRITE},
        }

        _d3d11_check(id, _state.device->CreateBuffer(&desc, nil, &result.buf)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.buf, base.get_debug_id_name(id))

        return result, true
    }

    _create_texture_2d :: proc(
        id:                 base.Debug_ID,
        format:             Texture_Format,
        usage:              Usage,
        size:               [2]i32,
        mips:               i32,
        array_depth:        i32,
        render_texture:      bool,
        rw_resource:        bool,
        data:               []byte,
    ) -> (result: _Resource_State, ok: bool) {
        bind_flags: d3d11.BIND_FLAGS

        if render_texture {
            if is_texture_format_depth_stencil(format) {
                // SHADER_RESOURCE so the depth buffer can be sampled. This requires a
                // typeless resource format (see _d3d11_texture_resource_format).
                bind_flags = {.DEPTH_STENCIL, .SHADER_RESOURCE}
            } else {
                bind_flags = {.RENDER_TARGET, .SHADER_RESOURCE}
            }
        } else {
            bind_flags = {.SHADER_RESOURCE}
        }

        if rw_resource {
            bind_flags += {.UNORDERED_ACCESS}
        }

        desc := d3d11.TEXTURE2D_DESC{
            // Depth formats must be created as typeless so we can make both a DSV and an SRV over them.
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

        initial_data := d3d11.SUBRESOURCE_DATA{
            pSysMem = raw_data(data),
            SysMemPitch = u32(int(size.x) * get_texture_format_pixel_size(format)),
        }

        initial_data_ptr: ^d3d11.SUBRESOURCE_DATA
        if data != nil {
            initial_data_ptr = &initial_data
        }

        _d3d11_check(id, _state.device->CreateTexture2D(&desc, initial_data_ptr, &result.tex2d)) or_return

        _d3d11_messages()
        _d3d11_setlabel(result.tex2d, base.get_debug_id_name(id))

        if is_texture_format_depth_stencil(format) {
            dsv_desc := d3d11.DEPTH_STENCIL_VIEW_DESC{
                Format = _d3d11_texture_depth_dsv_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {MipSlice = 0},
            }
            _d3d11_check(id, _state.device->CreateDepthStencilView(result.tex2d, &dsv_desc, &result.dsv)) or_return
            _d3d11_setlabel(result.dsv, base.get_debug_id_name(id))

            srv_desc := d3d11.SHADER_RESOURCE_VIEW_DESC{
                Format = _d3d11_texture_depth_srv_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                },
            }
            _d3d11_check(id, _state.device->CreateShaderResourceView(result.tex2d, &srv_desc, &result.srv)) or_return
            _d3d11_setlabel(result.srv, base.get_debug_id_name(id))

        } else if render_texture {
            _d3d11_check(id, _state.device->CreateRenderTargetView(result.tex2d, nil, &result.rtv)) or_return

            srv_desc := d3d11.SHADER_RESOURCE_VIEW_DESC{
                Format = _d3d11_texture_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                },
            }

            _d3d11_check(id, _state.device->CreateShaderResourceView(result.tex2d, &srv_desc, &result.srv)) or_return
            _d3d11_setlabel(result.srv, base.get_debug_id_name(id))

        } else {
            srv_desc := d3d11.SHADER_RESOURCE_VIEW_DESC{
                Format = _d3d11_texture_format(format),
            }

            if array_depth > 1 {
                srv_desc.ViewDimension = .TEXTURE2DARRAY
                srv_desc.Texture2DArray = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                    FirstArraySlice = 0,
                    ArraySize = u32(array_depth),
                }
            } else {
                srv_desc.ViewDimension = .TEXTURE2D
                srv_desc.Texture2D = {
                    MostDetailedMip = 0,
                    MipLevels = 1,
                }
            }

            _d3d11_check(id, _state.device->CreateShaderResourceView(result.tex2d, &srv_desc, &result.srv)) or_return
            _d3d11_setlabel(result.srv, base.get_debug_id_name(id))
        }

        _d3d11_messages()

        if rw_resource {
            uav_desc := d3d11.UNORDERED_ACCESS_VIEW_DESC{
                Format = _d3d11_texture_format(format),
                ViewDimension = .TEXTURE2D,
                Texture2D = {
                    MipSlice = 0,
                },
            }

            _d3d11_check(id, _state.device->CreateUnorderedAccessView(result.tex2d, &uav_desc, &result.uav)) or_return
            _d3d11_setlabel(result.uav, base.get_debug_id_name(id))
        }

        _d3d11_messages()

        return result, true
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Destroy
    //

    _destroy_shader :: proc(shader: Shader_State) {
        switch shader.kind {
        case .Invalid:  return
        case .Vertex:   shader.vs->Release()
        case .Pixel:    shader.ps->Release()
        case .Compute:  shader.cs->Release()
        }
        _d3d11_messages()
    }

    _destroy_resource :: proc(res: Resource_State) {
        switch res.kind {
        case .Invalid:
            assert(false)
            return
        case .Buffer, .Constants:
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
            res.tex3d->Release()
        }

        if res.srv != nil {
            res.srv->Release()
        }

        if res.uav != nil {
            res.uav->Release()
        }

        _d3d11_messages()
    }

    _destroy_bind_group :: proc(state: Bind_Group_State) {
        for it in state.smps  do it->Release()
        for it in state.cbufs do it->Release()
        for it in state.srvs  do it->Release()
        for it in state.uavs  do it->Release()
        _d3d11_messages()
    }

    _destroy_bind_layout :: proc(state: Bind_Layout_State) {
        // no-op
    }

    _destroy_graphics_pipeline :: proc(state: Graphics_Pipeline_State) {
        if state.blend != nil {
            state.blend->Release()
        }
        if state.rasterizer != nil {
            state.rasterizer->Release()
        }
        if state.depth_stencil != nil {
            state.depth_stencil->Release()
        }
        if state.input_layout != nil {
            state.input_layout->Release()
        }
        _d3d11_messages()
    }

    _destroy_compute_pipeline :: proc(state: Compute_Pipeline_State) {
        // no-op
    }



    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Set
    //

    _set_shader :: proc(shader: Shader_State) {
        switch shader.kind {
        case .Invalid: assert(false)
        case .Vertex:  _state.device_context->VSSetShader(shader.vs, nil, 0)
        case .Pixel:   _state.device_context->PSSetShader(shader.ps, nil, 0)
        case .Compute: _state.device_context->CSSetShader(shader.cs, nil, 0)
        }
        _d3d11_messages()
    }

    _set_resources :: proc(shaders: bit_set[Shader_Kind], srvs: []^d3d11.IShaderResourceView, start_slot: i32) {
        if .Vertex  in shaders do _state.device_context->VSSetShaderResources(StartSlot = u32(start_slot), NumViews = u32(len(srvs)), ppShaderResourceViews = raw_data(srvs))
        if .Pixel   in shaders do _state.device_context->PSSetShaderResources(StartSlot = u32(start_slot), NumViews = u32(len(srvs)), ppShaderResourceViews = raw_data(srvs))
        if .Compute in shaders do _state.device_context->CSSetShaderResources(StartSlot = u32(start_slot), NumViews = u32(len(srvs)), ppShaderResourceViews = raw_data(srvs))
        _d3d11_messages()
    }

    _set_samplers :: proc(shaders: bit_set[Shader_Kind], smps: []^d3d11.ISamplerState, start_slot: i32) {
        if .Vertex  in shaders do _state.device_context->VSSetSamplers(StartSlot = u32(start_slot), NumSamplers = u32(len(smps)), ppSamplers = raw_data(smps))
        if .Pixel   in shaders do _state.device_context->PSSetSamplers(StartSlot = u32(start_slot), NumSamplers = u32(len(smps)), ppSamplers = raw_data(smps))
        if .Compute in shaders do _state.device_context->CSSetSamplers(StartSlot = u32(start_slot), NumSamplers = u32(len(smps)), ppSamplers = raw_data(smps))
    }

    _set_constants :: proc(shaders: bit_set[Shader_Kind], cbufs: []^d3d11.IBuffer, offset_starts: []u32, offset_nums: []u32, start_slot: i32) {
        if .Vertex in shaders {
            _state.device_context->VSSetConstantBuffers1(
                StartSlot = u32(start_slot),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
                pFirstConstant = raw_data(offset_starts),
                pNumConstants = raw_data(offset_nums),
            )
        }

        if .Pixel in shaders {
            _state.device_context->PSSetConstantBuffers1(
                StartSlot = u32(start_slot),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
                pFirstConstant = raw_data(offset_starts),
                pNumConstants = raw_data(offset_nums),
            )
        }

        if .Compute in shaders {
            _state.device_context->CSSetConstantBuffers1(
                StartSlot = u32(start_slot),
                NumBuffers = u32(len(cbufs)),
                ppConstantBuffers = raw_data(cbufs),
                pFirstConstant = raw_data(offset_starts),
                pNumConstants = raw_data(offset_nums),
            )
        }

    }

    _set_cs_rw_resources :: proc(uavs: []^d3d11.IUnorderedAccessView, start_slot: i32) {
        _state.device_context->CSSetUnorderedAccessViews(
            StartSlot = u32(start_slot),
            NumUAVs = u32(len(uavs)),
            ppUnorderedAccessViews = raw_data(uavs),
            pUAVInitialCounts = nil,
        )
    }

    _set_vertex_buffer :: proc(slot: int, res: ^Resource_State, offset: int) {
        // TODO: unbind all at the end of a frame
        offset := u32(offset)
        stride := u32(res.size.y)
        _state.device_context->IASetVertexBuffers(
            StartSlot = u32(slot),
            NumBuffers = 1,
            ppVertexBuffers = &res.buf,
            pStrides = &stride,
            pOffsets = &offset,
        )
        _d3d11_messages()
    }

    _set_index_buffer :: proc(res: ^Resource_State, format: Index_Format, offset: int) {
        _state.device_context->IASetIndexBuffer(
            pIndexBuffer = res.buf,
            Format = _d3d11_index_format(format),
            Offset = u32(offset),
        )
        _d3d11_messages()
    }

    _unbind_vertex_buffers :: proc() {
        bufs:    [d3d11.IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]^d3d11.IBuffer
        strides: [d3d11.IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]u32
        offsets: [d3d11.IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]u32
        _state.device_context->IASetVertexBuffers(0, d3d11.IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT, &bufs[0], &strides[0], &offsets[0])
    }

    _unbind_index_buffers :: proc() {
        _state.device_context->IASetIndexBuffer(nil, .R32_UINT, 0)
    }

    _unbind_shaders :: proc(shaders: bit_set[Shader_Kind]) {
        if .Vertex  in shaders do _state.device_context->VSSetShader(nil, nil, 0)
        if .Pixel   in shaders do _state.device_context->PSSetShader(nil, nil, 0)
        if .Compute in shaders do _state.device_context->CSSetShader(nil, nil, 0)
    }

    _unbind_cs_rw_resources :: proc() {
        uavs: [MAX_PIPELINE_BIND_RW_RESOURCES]^d3d11.IUnorderedAccessView
        _state.device_context->CSSetUnorderedAccessViews(0, len(uavs), &uavs[0], nil)
    }

    _unbind_resources :: proc(shaders: bit_set[Shader_Kind]) {
        srvs: [MAX_PIPELINE_BIND_RESOURCES]^d3d11.IShaderResourceView
        if .Vertex in shaders do _state.device_context->VSSetShaderResources(0, len(srvs), &srvs[0])
        if .Pixel in shaders do _state.device_context->PSSetShaderResources(0, len(srvs), &srvs[0])
        if .Compute in shaders do _state.device_context->CSSetShaderResources(0, len(srvs), &srvs[0])
    }

    _unbind_constants :: proc(shaders: bit_set[Shader_Kind]) {
        cbufs: [MAX_PIPELINE_BIND_CONSTANTS]^d3d11.IBuffer
        if .Vertex in shaders do _state.device_context->VSSetConstantBuffers(0, len(cbufs), &cbufs[0])
        if .Pixel in shaders do _state.device_context->PSSetConstantBuffers(0, len(cbufs), &cbufs[0])
        if .Compute in shaders do _state.device_context->CSSetConstantBuffers(0, len(cbufs), &cbufs[0])
    }

    _unbind_samplers :: proc(shaders: bit_set[Shader_Kind]) {
        smps: [MAX_PIPELINE_BIND_SAMPLERS]^d3d11.ISamplerState
        if .Vertex in shaders do _state.device_context->VSSetSamplers(0, len(smps), &smps[0])
        if .Pixel in shaders do _state.device_context->PSSetSamplers(0, len(smps), &smps[0])
        if .Compute in shaders do _state.device_context->CSSetSamplers(0, len(smps), &smps[0])
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Actions
    //

    _begin_graphics_pass :: proc(id: base.Debug_ID, desc: Graphics_Pass_Desc) {
        rtvs: [d3d11.SIMULTANEOUS_RENDER_TARGET_COUNT]^d3d11.IRenderTargetView
        dsv: ^d3d11.IDepthStencilView

        if depth, depth_ok := _get_resource(desc.depth.resource); depth_ok {
            assert(depth.kind == .Texture2D)
            assert(depth.dsv != nil)

            dsv = depth.dsv

            switch desc.depth.clear_mode {
            case .Keep:
            case .Clear:
                assert(depth.dsv != nil)
                _state.device_context->ClearDepthStencilView(depth.dsv, {.DEPTH}, Depth = desc.depth.clear_val, Stencil = 0)
            }
        }

        resolution: [2]i32
        color_num := 0
        for color in desc.colors {
            color := color
            rtv: ^d3d11.IRenderTargetView
            if color.resource == SWAPCHAIN_HANDLE {
                rtv = _state.swapchain_rtv
                resolution = _state.swapchain_size
            } else {
                res := _get_resource(color.resource) or_break
                #partial switch res.kind {
                case .Texture2D:
                case:
                    assert(false)
                }
                rtv = res.rtv
                resolution = res.size.xy
            }

            assert(rtv != nil)
            rtvs[color_num] = rtv
            color_num += 1

            switch color.clear_mode {
            case .Keep:
            case .Clear:
                _state.device_context->ClearRenderTargetView(rtv, &color.clear_val)
            }
        }

        _state.device_context->OMSetRenderTargets(
            NumViews = u32(color_num),
            ppRenderTargetViews = color_num == 0 ? nil : &rtvs[0],
            pDepthStencilView = dsv,
        )

        viewport := d3d11.VIEWPORT{
            TopLeftX = 0,
            TopLeftY = 0,
            Width = f32(resolution.x),
            Height = f32(resolution.y),
            MinDepth = 0.0,
            MaxDepth = 1.0,
        }

        _state.device_context->RSSetViewports(1, &viewport)
    }

    _end_graphics_pass :: proc() {
        _state.prev_graphics_pip = {}
        _unbind_cs_rw_resources()
        _unbind_vertex_buffers()
        _unbind_index_buffers()
        _unbind_shaders({.Vertex, .Pixel, .Compute})
        _unbind_resources({.Vertex, .Pixel, .Compute})
        _unbind_constants({.Vertex, .Pixel, .Compute})
        _unbind_samplers({.Vertex, .Pixel, .Compute})
    }

    _set_bind_group :: proc(slot: int, bind_group: ^Bind_Group_State, offsets: []u32) {
        if len(bind_group.smps) > 0 {
            _set_samplers(bind_group.smp_stages, bind_group.smps[:], start_slot = i32(MAX_BIND_GROUP_SAMPLERS * slot))
        }

        if len(bind_group.srvs) > 0 {
            _set_resources(bind_group.srv_stages, bind_group.srvs[:], start_slot = i32(MAX_BIND_GROUP_RESOURCES * slot))
        }

        if len(bind_group.cbufs) > 0 {
            offset_starts: [MAX_BIND_GROUP_CONSTANTS]u32
            offset_nums:   [MAX_BIND_GROUP_CONSTANTS]u32

            index := 0
            for _, i in bind_group.consts {
                if i not_in bind_group.consts_dyn {
                    continue
                }

                assert(offsets[index] % 4 == 0)
                offset_starts[index] = offsets[index] / 4
                offset_nums[index] = u32(bind_group.consts_sizes[i]) / 4
                index += 1
            }

            _set_constants(
                bind_group.cbuf_stages,
                bind_group.cbufs[:],
                start_slot = i32(MAX_BIND_GROUP_CONSTANTS * slot),
                offset_starts = offset_starts[:],
                offset_nums = offset_nums[:],
            )
        }

        if len(bind_group.uavs) > 0 && _state.encoder.mode == .Compute {
            _set_cs_rw_resources(bind_group.uavs[:], start_slot = i32(MAX_BIND_GROUP_RW_RESOURCES * slot))
        }
    }

    _set_graphics_pipeline :: proc(pip: ^Graphics_Pipeline_State) {
        if pip.desc.topo != _state.prev_graphics_pip.desc.topo {
            _state.device_context->IASetPrimitiveTopology(_d3d11_topology(pip.desc.topo))
        }

        if pip.blend != _state.prev_graphics_pip.blend {
            _state.device_context->OMSetBlendState(pip.blend, BlendFactor = nil, SampleMask = 0xffff_ffff)
        }

        if pip.rasterizer != _state.prev_graphics_pip.rasterizer {
            _state.device_context->RSSetState(pip.rasterizer)
        }

        if pip.depth_stencil != _state.prev_graphics_pip.depth_stencil {
            _state.device_context->OMSetDepthStencilState(pip.depth_stencil, 0)
        }

        if pip.input_layout != _state.prev_graphics_pip.input_layout {
            _state.device_context->IASetInputLayout(pip.input_layout)
        }

        if pip.desc.vs != _state.prev_graphics_pip.desc.vs {
            if shader, shader_ok := _get_shader(pip.desc.vs); shader_ok {
                assert(shader.kind == .Vertex)
                _set_shader(shader^)
            }
        }

        if pip.desc.ps != _state.prev_graphics_pip.desc.ps {
            if shader, shader_ok := _get_shader(pip.desc.ps); shader_ok {
                assert(shader.kind == .Pixel)
                _set_shader(shader^)
            }
        }

        _state.prev_graphics_pip = pip^
        _d3d11_messages()
    }

    _begin_compute_pass :: proc(id: base.Debug_ID) {
        // no-op
    }

    _end_compute_pass :: proc() {
        _state.prev_compute_pip = {}
        _unbind_cs_rw_resources()
    }

    _set_compute_pipeline :: proc(pip: ^Compute_Pipeline_State) {
        if pip.desc.cs != _state.prev_compute_pip.desc.cs {
            if shader, shader_ok := _get_shader(pip.desc.cs); shader_ok {
                assert(shader.kind == .Compute)
                _set_shader(shader^)
            }
        }
        _state.prev_compute_pip = pip^
        _d3d11_messages()
    }

    _update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]byte) {
        switch res.usage {
        case .Immutable:
            assert(false)

        case .Dynamic:
            mapped: d3d11.MAPPED_SUBRESOURCE
            if !_d3d11_check(res.id, _state.device_context->Map(
                res.buf,
                Subresource = 0,
                MapType = .WRITE_DISCARD,
                MapFlags = {},
                pMappedResource = &mapped,
            )) {
                return
            }

            write_ptr := uintptr(mapped.pData) + uintptr(offset)
            for buf in buffers {
                runtime.mem_copy_non_overlapping(rawptr(write_ptr), raw_data(buf), len(buf))
                write_ptr += uintptr(len(buf))
            }

            _state.device_context->Unmap(res.buf, 0)

        case .Default:
            temp := _combine_buffer_writes_temp(buffers)

            _state.device_context->UpdateSubresource(
                pDstResource = res.buf,
                DstSubresource = 0,
                pDstBox = &d3d11.BOX{
                    left    = u32(offset),
                    top     = 0,
                    right   = u32(offset + len(temp)),
                    bottom  = 1,
                    front   = 0,
                    back    = 1,
                },
                pSrcData = raw_data(temp),
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
            mapped: d3d11.MAPPED_SUBRESOURCE
            if !_d3d11_check(res.id, _state.device_context->Map(
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

    _update_texture_2d :: proc(res: ^Resource_State, data: []byte, slice: i32) {
        sub := _d3d11_calc_subresource(0, slice, 1)
        _state.device_context->UpdateSubresource(
            pDstResource = res.tex2d,
            DstSubresource = sub,
            pDstBox = nil,
            pSrcData = raw_data(data),
            SrcRowPitch = u32(int(res.size.x) * get_texture_format_pixel_size(res.tex_format)),
            SrcDepthPitch = 0,
        )
        _d3d11_messages()
    }

    _draw_non_indexed :: proc(vertex_num: int, instance_num: int, vertex_offset: int, instance_offset: int) {
        _state.device_context->DrawInstanced(
            VertexCountPerInstance = u32(vertex_num),
            InstanceCount = u32(instance_num),
            StartVertexLocation = u32(vertex_offset),
            StartInstanceLocation = u32(instance_offset),
        )
        _d3d11_messages()
    }

    _draw_indexed :: proc(index_num: int, instance_num: int, index_offset: int, vertex_offset: int, instance_offset: int) {
        _state.device_context->DrawIndexedInstanced(
            IndexCountPerInstance = u32(index_num),
            InstanceCount = u32(instance_num),
            StartIndexLocation = u32(index_offset),
            BaseVertexLocation = i32(vertex_offset),
            StartInstanceLocation = u32(instance_offset),
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

    _d3d11_setlabel :: proc(self: ^d3d11.IDeviceChild, label: string) {
        buf: [128]u16
        wstr := windows.utf8_to_utf16_buf(buf[:], label)
        self->SetPrivateData(d3d11.WKPDID_D3DDebugObjectNameW_UUID, u32(size_of(u16) * len(wstr)), raw_data(wstr))
    }

    _d3d11_calc_subresource :: proc(mip: i32, slice: i32, mip_levels: i32) -> u32 {
        return u32(mip + (slice * mip_levels))
    }

    @(private = "file")
    _d3d11_check :: proc(id: base.Debug_ID, res: dxgi.HRESULT, expr := #caller_expression(res), loc := #caller_location) -> bool {
        level: base.Log_Level = .Error
        message := "none"

        switch transmute(u32)res {
        case 0:
            return true

        case 1:
            level = .Warning
            message = "S_FALSE: Successful but nonstandard completion (the precise meaning depends on context)"

        case 0x887C0002:
            message = "D3D11_ERROR_FILE_NOT_FOUND: The file was not found"
        case 0x887C0001:
            message = "D3D11_ERROR_TOO_MANY_UNIQUE_STATE_OBJECTS: There are too many unique instances of a particular type of state object"
        case 0x887C0003:
            message = "D3D11_ERROR_TOO_MANY_UNIQUE_VIEW_OBJECTS: There are too many unique instances of a particular type of view object"
        case 0x887C0004:
            message = "D3D11_ERROR_DEFERRED_CONTEXT_MAP_WITHOUT_INITIAL_DISCARD: The first call to ID3D11DeviceContext::Map after either ID3D11Device::CreateDeferredContext or ID3D11DeviceContext::FinishCommandList per Resource was not D3D11_MAP_WRITE_DISCARD"
        case 0x887A0001:
            message = "DXGI_ERROR_INVALID_CALL: The method call is invalid. For example, a method's parameter may not be a valid pointer"
        case 0x887A000A:
            message = "DXGI_ERROR_WAS_STILL_DRAWING: The previous blit operation that is transferring information to or from this surface is incomplete"
        case 0x887A002D:
            message = "DXGI_ERROR_SDK_COMPONENT_MISSING: An SDK component is missing or mismatched"
        case 0x80004005:
            message = "E_FAIL: Attempted to create a device with the debug layer enabled and the layer is not installed"
        case 0x80070057:
            message = "E_INVALIDARG: An invalid parameter was passed to the returning function"
        case 0x8007000E:
            message = "E_OUTOFMEMORY: Direct3D could not allocate sufficient memory to complete the call"
        case 0x80004001:
            message = "E_NOTIMPL: The method call isn't implemented with the passed parameter combination"
        }

        base.log(
            level = level,
            format = "D3D11 Error:\n\tMessage: %s\n\tSource: %s %s:%i\n\tExpression: %s",
            args = {
                message,
                base.get_debug_id_name(id),
                base.get_debug_id_file(id),
                id.line,
                expr,
            },
            loc = loc,
        )

        _d3d11_messages(loc)

        if level >= .Error {
            panic("D3D11 Error", loc = loc)
        }

        return false
    }

    @(disabled = RELEASE)
    _d3d11_messages :: proc(loc := #caller_location) {
        when !RELEASE {
            defer _state.info_queue->ClearStoredMessages()

            count := _state.info_queue->GetNumStoredMessages()
            for i in 0..<count {
                msg_size: uint
                _state.info_queue->GetMessage(i, nil, &msg_size)

                msg := cast(^d3d11.MESSAGE)make_multi_pointer([^]byte, msg_size, context.temp_allocator)
                _state.info_queue->GetMessage(i, msg, &msg_size)

                level: base.Log_Level
                switch msg.Severity {
                case .CORRUPTION: level = .Fatal
                case .ERROR: level = .Error
                case .WARNING: level = .Warning
                case .INFO: level = .Info
                case .MESSAGE: level = .Debug
                }

                base.log(level, "D3D11 Message:\n\t%v:\n\t%v", msg.Category, msg.pDescription, loc = loc)

                if msg.Severity == .CORRUPTION || msg.Severity == .ERROR {
                    panic("Error")
                }

                if VALIDATION && msg.Severity == .WARNING {
                    panic("Warning")
                }
            }
        }
    }

    _d3d11_usage :: proc(usage: Usage) -> d3d11.USAGE {
        switch usage {
        case .Default:   return .DEFAULT
        case .Immutable: return .IMMUTABLE
        case .Dynamic:   return .DYNAMIC
        }
        assert(false)
        return .DEFAULT
    }

    _d3d11_blend_op :: proc(blend_op: Blend_Op) -> d3d11.BLEND_OP {
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

    _d3d11_blend_factor :: proc(blend_factor: Blend_Factor) -> d3d11.BLEND {
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

    _d3d11_cpu_access :: proc(usage: Usage) -> d3d11.CPU_ACCESS_FLAGS {
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

    _d3d11_texture_bounds :: proc(bounds: Texture_Bounds) -> d3d11.TEXTURE_ADDRESS_MODE {
        switch bounds {
        case .Wrap:         return .WRAP
        case .Mirror:       return .MIRROR
        case .Clamp:        return .CLAMP
        }
        assert(false)
        return .WRAP
    }


    _d3d11_topology :: proc(topology: Topology) -> d3d11.PRIMITIVE_TOPOLOGY {
        switch topology {
        case .Invalid:      return .TRIANGLELIST
        case .Lines:        return .LINELIST
        case .Triangles:    return .TRIANGLELIST
        }
        assert(false)
        return .TRIANGLELIST
    }

    _d3d11_fill_mode :: proc(fill_mode: Fill_Mode) -> d3d11.FILL_MODE {
        switch fill_mode {
        case .Invalid:      return .SOLID
        case .Solid:        return .SOLID
        case .Wireframe:    return .WIREFRAME
        }
        assert(false)
        return .SOLID
    }

    _d3d11_cull_mode :: proc(cull_mode: Cull_Mode) -> d3d11.CULL_MODE {
        switch cull_mode {
        case .Invalid:  return .NONE
        case .None:     return .NONE
        case .Front:    return .FRONT
        case .Back:    return .BACK
        }
        assert(false)
        return .NONE
    }

    _d3d11_depth_write :: proc(depth_write: bool) -> d3d11.DEPTH_WRITE_MASK {
        if depth_write {
            return .ALL
        } else {
            return .ZERO
        }
        assert(false)
        return .ALL
    }

    _d3d11_comparison :: proc(op: Comparison_Op) -> d3d11.COMPARISON_FUNC {
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

    _d3d11_filter :: proc(filter: bit_set[Filter]) -> d3d11.FILTER {
        switch filter {
        case {}:                 return .MIN_MAG_MIP_POINT
        case {.Mip}:             return .MIN_MAG_POINT_MIP_LINEAR
        case {.Mag}:             return .MIN_POINT_MAG_LINEAR_MIP_POINT
        case {.Mag, .Mip}:       return .MIN_POINT_MAG_MIP_LINEAR
        case {.Min}:             return .MIN_LINEAR_MAG_MIP_POINT
        case {.Min, .Mip}:       return .MIN_LINEAR_MAG_POINT_MIP_LINEAR
        case {.Min, .Mag}:       return .MIN_MAG_LINEAR_MIP_POINT
        case {.Min, .Mag, .Mip}: return .MIN_MAG_MIP_LINEAR
        }
        assert(false)
        return .MIN_MAG_MIP_POINT
    }

    _d3d11_texture_depth_srv_format :: proc(format: Texture_Format) -> dxgi.FORMAT {
        #partial switch format {
        case .Depth_F32:            return .R32_FLOAT
        case .Depth_U16_Norm:       return .R16_UNORM
        case .Depth_U24_Norm_S_U8:  return .R24_UNORM_X8_TYPELESS
        }
        assert(false)
        return .UNKNOWN
    }

    _d3d11_texture_depth_dsv_format :: proc(format: Texture_Format) -> dxgi.FORMAT {
        #partial switch format {
        case .Depth_F32:            return .D32_FLOAT
        case .Depth_U16_Norm:       return .D16_UNORM
        case .Depth_U24_Norm_S_U8:  return .D24_UNORM_S8_UINT
        }
        assert(false)
        return .UNKNOWN
    }

    _d3d11_texture_format :: proc(format: Texture_Format) -> dxgi.FORMAT {
        switch format {
        case .Invalid:              return .UNKNOWN
        case .Swapchain:            return .B8G8R8A8_UNORM
        case .RGBA_F32:             return .R32G32B32A32_FLOAT
        case .RGBA_U32:             return .R32G32B32A32_UINT
        case .RGBA_S32:             return .R32G32B32A32_SINT
        case .RGBA_F16:             return .R16G16B16A16_FLOAT
        case .RGBA_U16_Norm:        return .R16G16B16A16_UNORM
        case .RGBA_U16:             return .R16G16B16A16_UINT
        case .RGBA_S16_Norm:        return .R16G16B16A16_SNORM
        case .RGBA_S16:             return .R16G16B16A16_SINT
        case .RG_F32:               return .R32G32_FLOAT
        case .RG_U32:               return .R32G32_UINT
        case .RG_S32:               return .R32G32_SINT
        case .RG_U10_A_U2_Norm:     return .R10G10B10A2_UNORM
        case .RG_U10_A_U2:          return .R10G10B10A2_UINT
        case .RG_F11_B_F10:         return .R11G11B10_FLOAT
        case .RGBA_U8_Norm:         return .R8G8B8A8_UNORM
        case .RGBA_U8:              return .R8G8B8A8_UINT
        case .RGBA_S8_Norm:         return .R8G8B8A8_SNORM
        case .RGBA_S8:              return .R8G8B8A8_SINT
        case .RG_F16:               return .R16G16_FLOAT
        case .RG_U16_Norm:          return .R16G16_UNORM
        case .RG_U16:               return .R16G16_UINT
        case .RG_S16_Norm:          return .R16G16_SNORM
        case .RG_S16:               return .R16G16_SINT
        case .R_F32:                return .R32_FLOAT
        case .R_U32:                return .R32_UINT
        case .R_S32:                return .R32_SINT
        case .RG_U8_Norm:           return .R8G8_UNORM
        case .RG_U8:                return .R8G8_UINT
        case .RG_S8_Norm:           return .R8G8_SNORM
        case .RG_S8:                return .R8G8_SINT
        case .R_F16:                return .R16_FLOAT
        case .R_U16_Norm:           return .R16_UNORM
        case .R_U16:                return .R16_UINT
        case .R_S16_Norm:           return .R16_SNORM
        case .R_S16:                return .R16_SINT
        case .R_U8_Norm:            return .R8_UNORM
        case .R_U8:                 return .R8_UINT
        case .R_S8_Norm:            return .R8_SNORM
        case .R_S8:                 return .R8_SINT
        case .Depth_F32:            return .R32_TYPELESS
        case .Depth_U16_Norm:       return .R16_TYPELESS
        case .Depth_U24_Norm_S_U8:  return .R24G8_TYPELESS
        }
        assert(false)
        return .R8G8B8A8_UNORM
    }

    _d3d11_vertex_format :: proc(format: Vertex_Format) -> dxgi.FORMAT {
        switch format {
        case .Invalid:
            assert(false)
        case .U8:            return .R8_UINT
        case .U8x2:          return .R8G8_UINT
        case .U8x4:          return .R8G8B8A8_UINT
        case .I8:            return .R8_SINT
        case .I8x2:          return .R8G8_SINT
        case .I8x4:          return .R8G8B8A8_SINT
        case .U8_Norm:       return .R8_UNORM
        case .U8x2_Norm:     return .R8G8_UNORM
        case .U8x4_Norm:     return .R8G8B8A8_UNORM
        case .I8_Norm:       return .R8_SNORM
        case .I8x2_Norm:     return .R8G8_SNORM
        case .I8x4_Norm:     return .R8G8B8A8_SNORM
        case .U16:           return .R16_UINT
        case .U16x2:         return .R16G16_UINT
        case .U16x4:         return .R16G16B16A16_UINT
        case .I16:           return .R16_SINT
        case .I16x2:         return .R16G16_SINT
        case .I16x4:         return .R16G16B16A16_SINT
        case .U16_Norm:      return .R16_UNORM
        case .U16x2_Norm:    return .R16G16_UNORM
        case .U16x4_Norm:    return .R16G16B16A16_UNORM
        case .I16_Norm:      return .R16_SNORM
        case .I16x2_Norm:    return .R16G16_SNORM
        case .I16x4_Norm:    return .R16G16B16A16_SNORM
        case .F16:           return .R16_FLOAT
        case .F16x2:         return .R16G16_FLOAT
        case .F16x4:         return .R16G16B16A16_FLOAT
        case .F32:           return .R32_FLOAT
        case .F32x2:         return .R32G32_FLOAT
        case .F32x3:         return .R32G32B32_FLOAT
        case .F32x4:         return .R32G32B32A32_FLOAT
        case .U32:           return .R32_UINT
        case .U32x2:         return .R32G32_UINT
        case .U32x3:         return .R32G32B32_UINT
        case .U32x4:         return .R32G32B32A32_UINT
        case .I32:           return .R32_SINT
        case .I32x2:         return .R32G32_SINT
        case .I32x3:         return .R32G32B32_SINT
        case .I32x4:         return .R32G32B32A32_SINT
        case .U10x3_U2_Norm: return .R10G10B10A2_UNORM
        }
        assert(false)
        return .UNKNOWN
    }

}