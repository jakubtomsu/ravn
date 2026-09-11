package ravn_gpu

import "../base"
import "vendor:wgpu"
import "base:runtime"
import "base:intrinsics"

_ :: wgpu
_ :: runtime
_ :: intrinsics

when BACKEND == BACKEND_WGPU {

    _WGPU_CALLBACK_MODE: wgpu.CallbackMode: .AllowProcessEvents

    _MAX_SAMPLERS :: 32

    _State :: struct {
        instance:               wgpu.Instance,
        adapter:                wgpu.Adapter,
        device:                 wgpu.Device,
        surface:                wgpu.Surface,
        surface_texture:        wgpu.SurfaceTexture,
        surface_view:           wgpu.TextureView,
        config:                 wgpu.SurfaceConfiguration,
        queue:                  wgpu.Queue,
        command_encoder:        wgpu.CommandEncoder,
        render_pass_encoder:    wgpu.RenderPassEncoder,
        compute_pass_encoder:   wgpu.ComputePassEncoder,
        draw_data_buf:          wgpu.Buffer,
        uniform_offset_align:   u32,
        samplers:               [dynamic; _MAX_SAMPLERS]_Sampler_State,
    }

    _Graphics_Pipeline_State :: struct #all_or_none {
        pip:    wgpu.RenderPipeline,
    }

    _Compute_Pipeline_State :: struct #all_or_none {
        pip:    wgpu.ComputePipeline,
    }

    _Shader_State :: struct #all_or_none {
        module: wgpu.ShaderModule,
    }

    _Blend_State :: struct #all_or_none {
        blend: wgpu.BlendState,
    }

    _Resource_State :: struct #raw_union {
        buf:    wgpu.Buffer,
        using _: struct {
            tex:        wgpu.Texture,
            tex_view:   wgpu.TextureView,
            surface:    wgpu.Surface,
        },
    }

    _Sampler_State :: struct #all_or_none {
        smp:    wgpu.Sampler,
        desc:   Sampler_Desc,
    }

    _Bind_Layout_State :: struct #all_or_none {
        bgl:    wgpu.BindGroupLayout,
    }

    _Bind_Group_State :: struct #all_or_none {
        bg: wgpu.BindGroup,
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: General
    //

    @(require_results)
    _init :: proc(native_window: rawptr) -> bool {

        inst_desc: wgpu.InstanceDescriptor
        _state.instance = wgpu.CreateInstance(&inst_desc)

        when ODIN_OS != .JS {
            wgpu.SetLogCallback(_wgpu_log_callback, nil)
        }

        if _state.instance == nil {
            base.log_err("WebGPU is not supported")
            return false
        }

        _state.surface = _wgpu_create_native_surface(_state.instance, native_window, ptr = nil)

        if _state.surface == nil {
            base.log_err("Failed to get WebGPU surface")
            return false
        }

        base.log_info("Requesting WebGPU adapter")

        adapter_options := wgpu.RequestAdapterOptions{
            compatibleSurface = _state.surface,
        }

        if ODIN_OS != .JS {
            adapter_options.powerPreference = .HighPerformance
        }

        wgpu.InstanceRequestAdapter(
            _state.instance,
            options = &adapter_options,
            callbackInfo = {
                callback = on_adapter,
                mode = _WGPU_CALLBACK_MODE,
            },
        )

        return true

        on_adapter :: proc "c" (
            status: wgpu.RequestAdapterStatus,
            adapter: wgpu.Adapter,
            message: string,
            userdata1, userdata2: rawptr,
        ) {
            context = _state.init_context

            base.log_debug("Got WebGPU Adapter")

            if status != .Success || adapter == nil {
                base.log_err("request adapter failure: [%v] %s", status, message)
                panic("WebGPU Adapter")
            }
            _state.adapter = adapter

            _request_wgpu_device()
        }
    }

    _request_wgpu_device :: proc() {
        base.log_info("Requesting WebGPU Device")

        required_features := [?]wgpu.FeatureName{
            // .TextureFormat16bitNorm,
        }

        for feature in required_features {
            if !wgpu.AdapterHasFeature(_state.adapter, feature) {
                base.log_err("WebGPU adapter doesn't have a required feature:", feature)
                panic("WebGPU Adapter Feature")
            }
        }

        wgpu.AdapterRequestDevice(_state.adapter,
            &wgpu.DeviceDescriptor{
                // requiredFeatureCount = len(required_features),
                // requiredFeatures = &required_features[0],
            },
            wgpu.RequestDeviceCallbackInfo{
                callback = on_device,
                mode = _WGPU_CALLBACK_MODE,
            },
        )

        return

        on_device :: proc "c" (
            status: wgpu.RequestDeviceStatus,
            device: wgpu.Device,
            message: string,
            userdata1, userdata2: rawptr,
        ) {
            context = _state.init_context

            base.log_debug("Got WebGPU Device")

            if status != .Success || device == nil {
                base.log_err("request device failure: [%v] %s", status, message)
                panic("WGPU Device request failed")
            }
            _state.device = device

            _state.queue = wgpu.DeviceGetQueue(_state.device)

            limits, limits_status := wgpu.DeviceGetLimits(_state.device)
            switch limits_status {
            case .Success:
            case .Error:
                panic("Failed to retreive device limits")
            }

            base.log_debug("WebGPU limits: %v", limits)

            _state.uniform_offset_align = limits.minUniformBufferOffsetAlignment

            _state.init_done = true

            base.log_debug("WebGPU fully initialized")
        }
    }

    _shutdown :: proc() {
        assert(_state.queue != nil)
        assert(_state.surface != nil)
        assert(_state.device != nil)
        assert(_state.adapter != nil)
        assert(_state.instance != nil)

        if _state.surface_texture.texture != nil {
            wgpu.TextureRelease(_state.surface_texture.texture)
        }

        wgpu.QueueRelease(_state.queue)
        wgpu.SurfaceRelease(_state.surface)
        wgpu.DeviceRelease(_state.device)
        wgpu.AdapterRelease(_state.adapter)
        wgpu.InstanceRelease(_state.instance)
    }

    _begin_frame :: proc() -> bool {
        assert(_state.adapter != {})
        assert(_state.device != {})
        assert(_state.surface_texture == {})
        assert(_state.surface_view == nil)
        assert(_state.command_encoder == nil)
        assert(_state.render_pass_encoder == nil)
        assert(_state.compute_pass_encoder == nil)
        assert(_state.surface != nil)

        // The browser event loop does this for us
        if ODIN_OS != .JS {
            wgpu.InstanceProcessEvents(_state.instance)
        }

        _state.surface_texture = wgpu.SurfaceGetCurrentTexture(_state.surface)

        switch _state.surface_texture.status {
        case .SuccessOptimal, .SuccessSuboptimal:
            // All good, could handle suboptimal here.

        case .Timeout, .Outdated, .Lost, .Occluded:
            base.log_info("%v", _state.surface_texture.status)
            // Skip this frame, and re-configure surface.
            if _state.surface_texture.texture != nil {
                wgpu.TextureRelease(_state.surface_texture.texture)
            }
            return false

        case .Error:
            // Fatal error
            base.log_err("wgpu. Error: SurfaceGetCurrentTexture status = %v", _state.surface_texture.status)
            panic("wgpu. SurfaceGetCurrentTexture Fatal Error")
        }

        // TODO
        // wgpu.DevicePushErrorScope(device, .Validation)
        // wgpu.DevicePushErrorScope(device, .OutOfMemory)
        // wgpu.DevicePushErrorScope(device, .Internal)

        _state.surface_view = wgpu.TextureCreateView(_state.surface_texture.texture, nil)

        _state.command_encoder = wgpu.DeviceCreateCommandEncoder(_state.device, nil)

        return true
    }

    _end_frame :: proc(sync: bool) {
        assert(_state.command_encoder != nil)
        assert(_state.queue != nil)
        assert(_state.surface != nil)

        if _state.render_pass_encoder != nil {
            wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
            wgpu.RenderPassEncoderRelease(_state.render_pass_encoder)
        }

        if _state.compute_pass_encoder != nil {
            wgpu.ComputePassEncoderEnd(_state.compute_pass_encoder)
            wgpu.ComputePassEncoderRelease(_state.compute_pass_encoder)
        }

        command_buffer := wgpu.CommandEncoderFinish(_state.command_encoder, nil)
        wgpu.CommandEncoderRelease(_state.command_encoder)

        wgpu.QueueSubmit(_state.queue, {
            command_buffer,
        })

        wgpu.SurfacePresent(_state.surface)

        wgpu.CommandBufferRelease(command_buffer)

        wgpu.TextureViewRelease(_state.surface_view)
        wgpu.TextureRelease(_state.surface_texture.texture)

        _state.command_encoder = nil
        _state.render_pass_encoder = nil
        _state.compute_pass_encoder = nil
        _state.surface_view = nil
        _state.surface_texture = {}
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Create
    //

    _get_or_create_sampler :: proc(desc: Sampler_Desc) -> (result: wgpu.Sampler) {
        // Only runs on pipeline creation, which must be rate.
        for sampler in _state.samplers {
            if sampler.desc == desc {
                return sampler.smp
            }
        }
        return _create_sampler(desc)
    }

    _create_sampler :: proc(desc: Sampler_Desc) -> (result: wgpu.Sampler) {
        base.log_debug("GPU: Creating WebGPU sampler")

        result = wgpu.DeviceCreateSampler(_state.device, &wgpu.SamplerDescriptor{
            label = "Sampler",
            addressModeU = _wgpu_texture_bounds(desc.bounds.x),
            addressModeV = _wgpu_texture_bounds(desc.bounds.y),
            addressModeW = _wgpu_texture_bounds(desc.bounds.z),
            minFilter = .Min in desc.filter ? .Linear : .Nearest,
            magFilter = .Mag in desc.filter ? .Linear : .Nearest,
            mipmapFilter = .Mip in desc.filter ? .Linear : .Nearest,
            lodMinClamp = desc.mip_min,
            lodMaxClamp = desc.mip_max,
            // compare = _wgpu_comparison(desc.comparison),
            compare = .Undefined,
            maxAnisotropy = clamp(u16(desc.max_aniso), 1, 16),
        })

        append(&_state.samplers, _Sampler_State{
            smp = result,
            desc = desc,
        })

        return result
    }

    _create_bind_layout :: proc(id: base.Debug_ID, desc: Bind_Layout_Desc) -> (result: _Bind_Layout_State, ok: bool) {
        base.log_debug("GPU: Creating WebGPU bind group layout")

        layout_entries: [dynamic; NUM_TOTAL_BIND_GROUP_SLOTS]wgpu.BindGroupLayoutEntry
        for slot in desc.slots {
            entry := wgpu.BindGroupLayoutEntry{
                binding = u32(slot.index + _bind_layout_slot_kind_shift(slot.kind)),
                visibility = _wgpu_stage_flags(slot.stages),
            }

            switch slot.kind {
            case .Sampler:
                entry.sampler = wgpu.SamplerBindingLayout{type = .Filtering}
            case .Constants:
                entry.buffer = wgpu.BufferBindingLayout{type = wgpu.BufferBindingType.Uniform}
            case .Constants_Dynamic:
                entry.buffer = wgpu.BufferBindingLayout{type = wgpu.BufferBindingType.Uniform, hasDynamicOffset = true}
            case .Resource_Buffer:
                entry.buffer = wgpu.BufferBindingLayout{type = .ReadOnlyStorage}
            case .Resource_Texture_2D:
                entry.texture = wgpu.TextureBindingLayout{sampleType = wgpu.TextureSampleType.Float, viewDimension = ._2D}
            case .Resource_Texture_2D_Array:
                entry.texture = wgpu.TextureBindingLayout{sampleType = wgpu.TextureSampleType.Float, viewDimension = ._2DArray}
            case .Resource_Texture_3D:
                entry.texture = wgpu.TextureBindingLayout{sampleType = wgpu.TextureSampleType.Float, viewDimension = ._3D}
            case .RW_Resource_Buffer:
                entry.buffer = wgpu.BufferBindingLayout{type = .Storage}
            case .RW_Resource_Texture_2D:
                entry.storageTexture = wgpu.StorageTextureBindingLayout{access = .ReadWrite, format = _wgpu_texture_format(slot.format), viewDimension = ._2D}
            case .RW_Resource_Texture_2D_Array:
                entry.storageTexture = wgpu.StorageTextureBindingLayout{access = .ReadWrite, format = _wgpu_texture_format(slot.format), viewDimension = ._2DArray}
            case .RW_Resource_Texture_3D:
                entry.storageTexture = wgpu.StorageTextureBindingLayout{access = .ReadWrite, format = _wgpu_texture_format(slot.format), viewDimension = ._3D}
            }

            append(&layout_entries, entry)
        }

        result.bgl = wgpu.DeviceCreateBindGroupLayout(_state.device, &wgpu.BindGroupLayoutDescriptor{
            label = base.get_debug_id_name(id),
            entryCount = uint(len(layout_entries)),
            entries = &layout_entries[0],
        })

        if result.bgl == nil {
            base.log_err("WGPU: Failed to create bind group layout")
            return {}, false
        }

        return result, true
    }

    _create_bind_group :: proc(id: base.Debug_ID, desc: Bind_Group_Desc) -> (result: _Bind_Group_State, ok: bool) {
        base.log_debug("GPU: Creating WebGPU bind_group '%s'", base.get_debug_id_name(id))

        bind_layout, bind_layout_ok := _get_bind_layout(desc.layout)
        base.assert_id(id, bind_layout_ok)

        group_entries: [dynamic; NUM_TOTAL_BIND_GROUP_SLOTS]wgpu.BindGroupEntry
        for slot, i in desc.slots {
            layout_slot := bind_layout.desc.slots[i]

            entry := wgpu.BindGroupEntry{
                binding = u32(slot.index + _bind_layout_slot_kind_shift(layout_slot.kind)),
            }

            if slot.resource != {} {
                base.assert_id(id, slot.sampler == {})
                res, res_ok := _get_resource(slot.resource)
                base.assert_id(id, res_ok)

                switch res.kind {
                case .Invalid:
                    base.assert_id(id, false)
                case .Constants:
                    entry.buffer = res.buf
                    entry.size = u64(res.size.x)
                case .Buffer:
                    base.assert_id(id, res.size.x % 4 == 0)
                    entry.size = u64(res.size.x)
                    entry.buffer = res.buf
                case .Texture2D:
                    entry.textureView = res.tex_view
                case .Texture3D:
                    entry.textureView = res.tex_view
                }

            } else {
                base.assert_id(id, slot.sampler != {})
                entry.sampler = _get_or_create_sampler(slot.sampler)
            }

            append(&group_entries, entry)
        }

        result.bg = wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
            label = base.get_debug_id_name(id),
            layout = bind_layout.bgl,
            entryCount = uint(len(group_entries)),
            entries = &group_entries[0],
        })

        if result.bg == nil {
            base.log_err("WGPU: Failed to create bind group")
            return {}, false
        }

        return result, true
    }

    _create_graphics_pipeline :: proc(id: base.Debug_ID, desc: Graphics_Pipeline_Desc) -> (result: _Graphics_Pipeline_State, ok: bool) {
        base.log_debug("GPU: Creating WebGPU graphics pipeline '%s'", base.get_debug_id_name(id))

        bind_layouts: [dynamic; MAX_PIPELINE_BIND_GROUPS]wgpu.BindGroupLayout
        for handle in desc.bind_layouts {
            if handle == {} {
                break
            }
            bind_layout, bind_layout_ok := _get_bind_layout(handle)
            base.assert_id(id, bind_layout_ok)
            append(&bind_layouts, bind_layout.bgl)
        }

        pip_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
            label = base.get_debug_id_name(id),
            bindGroupLayoutCount = uint(len(bind_layouts)),
            bindGroupLayouts = len(bind_layouts) == 0 ? nil : &bind_layouts[0],
        })

        if pip_layout == nil {
            base.log_err("WGPU: Failed to create pipeline layout")
            return {}, false
        }

        defer wgpu.PipelineLayoutRelease(pip_layout)

        // NOTE: fill mode is ignored.

        ps, ps_ok := _get_shader(desc.ps)
        vs, vs_ok := _get_shader(desc.vs)

        base.assert_id(id, ps_ok)
        base.assert_id(id, vs_ok)
        base.assert_id(id, ps.kind == .Pixel)
        base.assert_id(id, vs.kind == .Vertex)

        color_targets_num := 0
        color_targets: [MAX_BOUND_RENDER_TEXTURES]wgpu.ColorTargetState

        for color, i in desc.color_format {
            if color == .Invalid {
                break
            }

            color_targets_num += 1

            blend := desc.blends[i]
            blend_state: ^wgpu.BlendState

            if blend != {} {
                blend_state = &wgpu.BlendState{
                    color = wgpu.BlendComponent{
                        operation = _wgpu_blend_op(blend.op_color),
                        srcFactor = _wgpu_blend_factor(blend.src_color),
                        dstFactor = _wgpu_blend_factor(blend.dst_color),
                    },
                    alpha = wgpu.BlendComponent{
                        operation = _wgpu_blend_op(blend.op_alpha),
                        srcFactor = _wgpu_blend_factor(blend.src_alpha),
                        dstFactor = _wgpu_blend_factor(blend.dst_alpha),
                    },
                }
            }

            color_targets[i] = wgpu.ColorTargetState{
                format = _wgpu_texture_format(color),
                blend = blend_state,
                writeMask = wgpu.ColorWriteMaskFlags{.Red, .Green, .Blue, .Alpha},
            }
        }

        depth_stencil: ^wgpu.DepthStencilState

        if desc.depth_format != .Invalid {
            if _depth_enable(desc.depth_comparison, desc.depth_write) {
                depth_stencil = &wgpu.DepthStencilState{
                    format = _wgpu_texture_format(desc.depth_format),
                    depthWriteEnabled = desc.depth_write ? .True : .False,
                    depthCompare = _wgpu_comparison(desc.depth_comparison),
                    stencilFront = wgpu.StencilFaceState{
                        passOp      = .Keep,
                        failOp      = .Keep,
                        depthFailOp = .Keep,
                        compare     = .Always,
                    },
                    stencilBack = wgpu.StencilFaceState{
                        passOp      = .Keep,
                        failOp      = .Keep,
                        depthFailOp = .Keep,
                        compare     = .Always,
                    },
                    stencilReadMask = 0,
                    stencilWriteMask = 0,
                    depthBias = desc.depth_bias,
                    depthBiasSlopeScale = 0,
                    depthBiasClamp = 0,
                }
            } else {
                    depth_stencil = &wgpu.DepthStencilState{
                    format = _wgpu_texture_format(desc.depth_format),
                    depthWriteEnabled = .False,
                    depthCompare = .Always,
                    stencilFront = wgpu.StencilFaceState{
                        passOp      = .Keep,
                        failOp      = .Keep,
                        depthFailOp = .Keep,
                        compare     = .Always,
                    },
                    stencilBack = wgpu.StencilFaceState{
                        passOp      = .Keep,
                        failOp      = .Keep,
                        depthFailOp = .Keep,
                        compare     = .Always,
                    },
                }
            }
        }

        num_slots := 0
        vertex_buffers: [dynamic; MAX_PIPELINE_VERTEX_LAYOUTS]wgpu.VertexBufferLayout
        for layout, layout_index in desc.vertex_layouts {
            if layout == {} {
                continue
            }

            attribs := make([dynamic]wgpu.VertexAttribute, 0, MAX_VERTEX_LAYOUT_SLOTS, context.temp_allocator)
            offset := 0

            for format in layout.slots {
                if format == {} {
                    break
                }

                attrib := wgpu.VertexAttribute{
                    format = _wgpu_vertex_format(format),
                    offset = u64(offset),
                    shaderLocation = u32(num_slots),
                }

                append(&attribs, attrib)
                offset += get_vertex_format_size(format)
                offset = runtime.align_forward_int(offset, 4)
                num_slots += 1
            }

            buffer := wgpu.VertexBufferLayout{
                stepMode = layout.mode == .Instance ? .Instance : .Vertex,
                arrayStride = u64(offset),
                attributeCount = len(attribs),
                attributes = raw_data(attribs),
            }

            append(&vertex_buffers, buffer)
        }

        base.eprintfln("%#", vertex_buffers[:])

        result.pip = wgpu.DeviceCreateRenderPipeline(_state.device, &{
            label = base.get_debug_id_name(id),
            layout = pip_layout,
            primitive = wgpu.PrimitiveState{
                topology = _wgpu_topology(desc.topo),
                stripIndexFormat = .Undefined,
                frontFace = .CCW,
                cullMode = _wgpu_cull_mode(desc.cull),
                unclippedDepth = false,
            },
            vertex = wgpu.VertexState{
                module = vs.module,
                entryPoint = "vs_main",
                constantCount = 0,
                constants = nil, // push constants not available
                bufferCount = uint(len(vertex_buffers)),
                buffers = len(vertex_buffers) == 0 ? nil : &vertex_buffers[0],
            },
            fragment = &wgpu.FragmentState{
                module = ps.module,
                entryPoint = "ps_main",
                constantCount = 0,
                constants = nil,
                targetCount = uint(color_targets_num),
                targets = &color_targets[0],
            },
            depthStencil = depth_stencil,
            multisample = {
                count = 1,
                mask = 0xffff_ffff,
                alphaToCoverageEnabled = false,
            },
        })

        if result.pip == nil {
            base.log_err("WGPU: Failed to create pipeline")
            return {}, false
        }

        return result, true
    }

    _create_compute_pipeline :: proc(id: base.Debug_ID, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline_State, ok: bool) {
        base.log_debug("GPU: Creating WebGPU compute pipeline '%s'", base.get_debug_id_name(id))

        bind_layouts: [dynamic; MAX_PIPELINE_BIND_GROUPS]wgpu.BindGroupLayout
        for handle in desc.bind_layouts {
            if handle == {} {
                break
            }
            bind_layout, bind_layout_ok := _get_bind_layout(handle)
            base.assert_id(id, bind_layout_ok)
            append(&bind_layouts, bind_layout.bgl)
        }

        pip_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
            label = base.get_debug_id_name(id),
            bindGroupLayoutCount = uint(len(bind_layouts)),
            bindGroupLayouts = len(bind_layouts) == 0 ? nil : &bind_layouts[0],
        })

        if pip_layout == nil {
            base.log_err("WGPU: Failed to create pipeline layout")
            return {}, false
        }

        defer wgpu.PipelineLayoutRelease(pip_layout)

        cs, cs_ok := _get_shader(desc.cs)
        base.assert_id(id, cs_ok)

        result.pip = wgpu.DeviceCreateComputePipeline(
            _state.device,
            &wgpu.ComputePipelineDescriptor{
                label = base.get_debug_id_name(id),
                layout = pip_layout,
                compute = wgpu.ComputeState{
                    module = cs.module,
                    entryPoint = "cs_main",
                    constants = nil,
                    constantCount = 0,
                },
            },
        )

        if result.pip == nil {
            return {}, false
        }

        return result, true
    }

    _resize_swapchain :: proc(window: rawptr, size: [2]i32) -> (ok: bool) {
        _state.config = wgpu.SurfaceConfiguration {
            device      = _state.device,
            usage       = { .RenderAttachment },
            format      = .BGRA8Unorm,
            width       = u32(size.x),
            height      = u32(size.y),
            presentMode = .Fifo,
            alphaMode   = .Opaque,
        }

        wgpu.SurfaceConfigure(_state.surface, &_state.config)

        if _state.surface == nil {
            return false
        }

        return true
    }

    _create_constants :: proc(id: base.Debug_ID, item_size: i32, item_num: i32) -> (result: _Resource_State, ok: bool) {
        size: u64
        if item_num > 1 {
            size = u64(runtime.align_forward_int(int(item_size), int(_state.uniform_offset_align))) * u64(item_num)
        } else {
            size = u64(item_size) * u64(item_num)
        }

        result.buf = wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor{
            label = base.get_debug_id_name(id),
            usage = {.Uniform, .CopyDst},
            size = size,
            mappedAtCreation = false,
        })

        if result.buf == nil {
            return {}, false
        }

        return result, true
    }

    _create_shader :: proc(id: base.Debug_ID, data: []u8, kind: Shader_Kind) -> (result: _Shader_State, ok: bool) {
        result.module = wgpu.DeviceCreateShaderModule(_state.device, &wgpu.ShaderModuleDescriptor{
            nextInChain = &wgpu.ShaderSourceWGSL{
                sType = .ShaderSourceWGSL,
                code  = string(data),
            },
            label = base.get_debug_id_name(id),
        })

        if result.module == nil {
            return {}, false
        }

        return result, true
    }

    _create_texture_2d :: proc(
        id: base.Debug_ID,
        format: Texture_Format,
        size: [2]i32,
        usage: Usage,
        mips: i32,
        array_depth: i32,
        render_texture: bool,
        rw_resource: bool,
        data: []byte,
    ) -> (result: _Resource_State, ok: bool) {
        usage: wgpu.TextureUsageFlags = {.TextureBinding}

        if render_texture {
            usage += {.RenderAttachment}
        } else {
            usage += {.CopyDst}
        }

        if rw_resource {
            usage += {.StorageBinding}
        }

        formats := [?]wgpu.TextureFormat{
            _wgpu_texture_format(format),
        }

        tex_desc := wgpu.TextureDescriptor{
            label = base.get_debug_id_name(id),
            usage = usage,
            dimension = ._2D,
            size = {
                width = u32(size.x),
                height = u32(size.y),
                depthOrArrayLayers = u32(array_depth),
            },
            format = _wgpu_texture_format(format),
            mipLevelCount = u32(mips),
            sampleCount = u32(1),
            viewFormatCount = len(formats),
            viewFormats = &formats[0],
        }

        result.tex = wgpu.DeviceCreateTexture(_state.device, &tex_desc)

        if result.tex == nil {
            return {}, false
        }

        row_bytes := u32(get_texture_format_pixel_size(format) * int(size.x))

        // assert(row_bytes % 256 == 0)

        if data != nil {
            wgpu.QueueWriteTexture(_state.queue,
                &wgpu.TexelCopyTextureInfo{
                    texture = result.tex,
                    mipLevel = 0,
                    origin = {0, 0, 0},
                    aspect = .All,
                },
                raw_data(data),
                dataSize = len(data),
                dataLayout = &wgpu.TexelCopyBufferLayout{
                    offset = 0,
                    bytesPerRow = row_bytes,
                    rowsPerImage = u32(size.y),
                },
                writeSize = &wgpu.Extent3D{
                    width = u32(size.x),
                    height = u32(size.y),
                    depthOrArrayLayers = u32(array_depth),
                },
            )
        }

        result.tex_view = wgpu.TextureCreateView(result.tex, &wgpu.TextureViewDescriptor{
	        label = base.get_debug_id_name(id),
	        format = formats[0],
	        dimension = ._2DArray,
	        baseMipLevel = 0,
	        mipLevelCount = u32(mips),
	        baseArrayLayer = 0,
	        arrayLayerCount = u32(array_depth),
	        aspect = wgpu.TextureAspect.All, // tf is this
	        usage = usage,
        })

        if result.tex_view == nil {
            return {}, false
        }

        return result, true
    }

    _create_buffer :: proc(
        id:     base.Debug_ID,
        kind:   Buffer_Kind,
        stride: i32,
        size:   i32,
        usage:  Usage,
        data:   []u8,
    ) -> (result: _Resource_State, ok: bool) {
        result.buf = wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor{
            label            = base.get_debug_id_name(id),
            usage            = _wgpu_buffer_usage(usage) + _wgpu_buffer_kind(kind),
            size             = u64(size),
            mappedAtCreation = data != nil,
        })

        if result.buf == nil {
            return {}, false
        }

        if data != nil {
            assert(len(data) <= int(size))
            mapping := wgpu.RawBufferGetMappedRange(result.buf, offset = 0, size = len(data))
            intrinsics.mem_copy_non_overlapping(mapping, raw_data(data), len(data))
            wgpu.BufferUnmap(result.buf)
        }

        return result, true
    }



    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Destroy
    //

    _destroy_shader :: proc(shader: Shader_State) {
        wgpu.ShaderModuleRelease(shader.module)
    }

    _destroy_resource :: proc(res: Resource_State) {
        switch res.kind {
        case .Invalid:
            base.assert_id(res.id, false)

        case .Buffer, .Constants:
            wgpu.BufferDestroy(res.buf)

        case .Texture2D, .Texture3D:
            wgpu.TextureDestroy(res.tex)
        }
    }

    _destroy_bind_group :: proc(state: Bind_Group_State) {
        wgpu.BindGroupRelease(state.bg)
    }

    _destroy_bind_layout :: proc(state: Bind_Layout_State) {
        wgpu.BindGroupLayoutRelease(state.bgl)
    }

    _destroy_graphics_pipeline :: proc(state: Graphics_Pipeline_State) {
        wgpu.RenderPipelineRelease(state.pip)
    }

    _destroy_compute_pipeline :: proc(state: Compute_Pipeline_State) {
        wgpu.ComputePipelineRelease(state.pip)
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Actions
    //

    _begin_graphics_pass :: proc(id: base.Debug_ID, desc: Graphics_Pass_Desc) {
        assert(_state.render_pass_encoder == nil)

        num_color_atts := 0
        color_atts: [MAX_BOUND_RENDER_TEXTURES]wgpu.RenderPassColorAttachment

        for color, i in desc.colors {
            view: wgpu.TextureView
            if color.resource == SWAPCHAIN_HANDLE {
                view = _state.surface_view
            } else {
                res := _get_resource(color.resource) or_break
                #partial switch res.kind {
                case .Texture2D:
                    view = res.tex_view
                case:
                    base.log_err("Invalid pass color, must be a Texture2D")
                }
            }

            num_color_atts += 1

            assert(view != nil)

            color_atts[i] = {
                view = view,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                resolveTarget = nil,
                loadOp = _wgpu_clear_mode(color.clear_mode),
                storeOp = .Store,
                clearValue = {
                    f64(color.clear_val.r),
                    f64(color.clear_val.g),
                    f64(color.clear_val.b),
                    f64(color.clear_val.a),
                },
            }
        }

        assert(color_atts != {})

        depth_stencil: ^wgpu.RenderPassDepthStencilAttachment
        if res, res_ok := _get_resource(desc.depth.resource); res_ok {
            depth_stencil = &{
                view = res.tex_view,
                depthLoadOp = _wgpu_clear_mode(desc.depth.clear_mode),
                depthStoreOp = .Store,
                depthClearValue = desc.depth.clear_val,
                depthReadOnly = false,
                stencilLoadOp = .Undefined,
                stencilStoreOp = .Undefined, // for now
                stencilClearValue = 0,
                stencilReadOnly = false,
            }
        }

        _state.render_pass_encoder = wgpu.CommandEncoderBeginRenderPass(
            _state.command_encoder,
            &wgpu.RenderPassDescriptor{
                label = base.get_debug_id_name(id),
                colorAttachmentCount = uint(num_color_atts),
                colorAttachments = num_color_atts == 0 ? nil : &color_atts[0],
                depthStencilAttachment = depth_stencil,
            },
        )
    }

    _end_graphics_pass :: proc() {
        assert(_state.render_pass_encoder != nil)
        wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
        _state.render_pass_encoder = nil
    }

    _set_vertex_buffer :: proc(slot: int, res: ^Resource_State, offset: int) {
        wgpu.RenderPassEncoderSetVertexBuffer(
            _state.render_pass_encoder,
            slot = u32(slot),
            buffer = res.buf,
            offset = u64(offset),
            size = u64(res.size.x),
        )
    }

    _set_index_buffer :: proc(res: ^Resource_State, format: Index_Format, offset: int) {
        wgpu.RenderPassEncoderSetIndexBuffer(
            _state.render_pass_encoder,
            buffer = res.buf,
            format = _wgpu_index_format(format),
            offset = u64(offset),
            size = u64(res.size.x),
        )
    }

    _set_graphics_pipeline :: proc(
        curr_pip: ^Graphics_Pipeline_State,
        curr: Graphics_Pipeline_Desc,
        prev: Graphics_Pipeline_Desc,
    ) {
        assert(curr_pip.pip != nil)
        base.assert_id(curr_pip.id, _state.render_pass_encoder != nil)
        wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, curr_pip.pip)
    }

    _begin_compute_pass :: proc(id: base.Debug_ID) {
        base.assert_id(id, _state.compute_pass_encoder == nil)
        _state.compute_pass_encoder = wgpu.CommandEncoderBeginComputePass(
            _state.command_encoder,
            &wgpu.ComputePassDescriptor{
                label = base.get_debug_id_name(id),
            },
        )
    }

    _end_compute_pass :: proc() {
        assert(_state.compute_pass_encoder != nil)
        wgpu.ComputePassEncoderEnd(_state.compute_pass_encoder)
        _state.compute_pass_encoder = nil
    }

    _set_compute_pipeline :: proc(curr_pip: ^Compute_Pipeline_State, prev: Compute_Pipeline_Desc) {
        assert(_state.compute_pass_encoder != nil)
        wgpu.ComputePassEncoderSetPipeline(_state.compute_pass_encoder, curr_pip.pip)
    }

    _update_buffer :: proc(res: ^Resource_State, offset: int, buffers: [][]byte) {
        temp := _combine_buffer_writes_temp(buffers)

        wgpu.QueueWriteBuffer(_state.queue,
            res.buf,
            bufferOffset = u64(offset),
            data = raw_data(temp),
            size = uint(len(temp)),
        )
    }

    _update_constants :: proc(res: ^Resource_State, data: []u8) {
        if res.size.y == 1 {
            wgpu.QueueWriteBuffer(_state.queue,
                res.buf,
                bufferOffset = 0,
                data = raw_data(data),
                size = uint(len(data)),
            )
        } else {
            // Must respect alignment for dynamic offsets.
            // NOTE: is many QueueWriteBuffer calls better than a single big with our own preallocated buffer?

            base.assert_id(res.id, len(data) % int(res.size.x) == 0)

            num_items := len(data) / int(res.size.x)

            aligned_size := runtime.align_forward_int(int(res.size.x), int(_state.uniform_offset_align))

            for i in 0..<num_items {
                wgpu.QueueWriteBuffer(_state.queue,
                    res.buf,
                    bufferOffset = u64(aligned_size * i),
                    data = &data[int(res.size.x) * i],
                    size = uint(res.size.x),
                )
            }
        }
    }

    _update_texture_2d :: proc(res: ^Resource_State, data: []byte, slice: i32) {
        base.assert_id(res.id, res.tex_format != .Invalid)

        row_bytes := u32(get_texture_format_pixel_size(res.tex_format) * int(res.size.x))
        wgpu.QueueWriteTexture(_state.queue,
            data = raw_data(data),
            dataSize = len(data),
            destination = &wgpu.TexelCopyTextureInfo{
                texture = res.tex,
                mipLevel = 0,
                origin = {0, 0, u32(slice)},
                aspect = .All,
            },
            dataLayout = &wgpu.TexelCopyBufferLayout{
                offset = 0,
	            bytesPerRow = row_bytes,
	            rowsPerImage = u32(res.size.y),
            },
            writeSize = &wgpu.Extent3D{
                width = u32(res.size.x),
                height = u32(res.size.y),
                depthOrArrayLayers = 1,
            },
        )
    }

    _set_bind_group :: proc(slot: int, bind_group: ^Bind_Group_State, offsets: []u32) {
        switch _state.encoder.mode {
        case .None:
            base.assert_id(bind_group.id, false)
        case .Graphics:
            wgpu.RenderPassEncoderSetBindGroup(
                _state.render_pass_encoder,
                groupIndex = u32(slot),
                group = bind_group.bg,
                dynamicOffsets = offsets[:],
            )
        case .Compute:
            wgpu.ComputePassEncoderSetBindGroup(
                _state.compute_pass_encoder,
                groupIndex = u32(slot),
                group = bind_group.bg,
                dynamicOffsets = offsets[:],
            )
        }
    }

    _draw_non_indexed :: proc(vertex_num: u32, instance_num: u32) {
        wgpu.RenderPassEncoderDraw(
            _state.render_pass_encoder,
            vertexCount = vertex_num,
            instanceCount = instance_num,
            firstVertex = 0,
            firstInstance = 0,
        )
    }

    _draw_indexed :: proc(index_num: u32, instance_num: u32, index_offset: u32) {
        wgpu.RenderPassEncoderDrawIndexed(
            _state.render_pass_encoder,
            indexCount = index_num,
            instanceCount = instance_num,
            firstIndex = index_offset,
            baseVertex = 0,
            firstInstance = 0,
        )
    }

    _dispatch_compute :: proc(size: [3]i32) {
        wgpu.ComputePassEncoderDispatchWorkgroups(
            _state.compute_pass_encoder,
            workgroupCountX = u32(size.x),
            workgroupCountY = u32(size.y),
            workgroupCountZ = u32(size.z),
        )
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Misc
    //

    _wgpu_log_callback :: proc "c" (level: wgpu.LogLevel, msg: wgpu.StringView, userdata: rawptr) {
        context = _state.init_context
        base.log(wgpu.ConvertWGPUToOdinLogLevel(level), "WGPU: %s", msg)
    }

    _wgpu_wait :: proc(future: wgpu.Future) {
        when _WGPU_CALLBACK_MODE == .WaitAnyOnly {
            info := wgpu.FutureWaitInfo{
                future = future,
            }
            res := wgpu.InstanceWaitAny(_state.instance, 1, &info, max(u64))
            if res == .Success {
                return
            }
            base.log_err("WGPU Future wait failed: %v", res)
        }
    }

    _wgpu_clear_mode :: proc(mode: Clear_Mode) -> wgpu.LoadOp {
        switch mode {
        case .Keep: return .Load
        case .Clear: return .Clear
        }
        assert(false)
        return .Load
    }

    _wgpu_stage_flags :: proc(flags: bit_set[Shader_Kind]) -> (result: wgpu.ShaderStageFlags) {
        assert(flags != {})
        if .Vertex  in flags do result += {.Vertex}
        if .Pixel   in flags do result += {.Fragment}
        if .Compute in flags do result += {.Compute}
        return result
    }

    _wgpu_buffer_kind :: proc(kind: Buffer_Kind) -> wgpu.BufferUsageFlags {
        switch kind {
        case .Invalid: return {}
        case .Storage: return {.Storage}
        case .Index:   return {.Index}
        case .Vertex:  return {.Vertex}
        }
        assert(false)
        return {.CopyDst}
    }

    _wgpu_buffer_usage :: proc(usage: Usage) -> wgpu.BufferUsageFlags {
        switch usage {
        case .Default:   return {.CopyDst}
        case .Immutable: return {}
        case .Dynamic:   return {.CopyDst}
        }
        assert(false)
        return {.CopyDst}
    }

    _wgpu_blend_op :: proc(blend_op: Blend_Op) -> wgpu.BlendOperation {
        switch blend_op {
            case .Add: return .Add
            case .Sub: return .Subtract
            case .Reverse_Sub: return .ReverseSubtract
            case .Min: return .Min
            case .Max: return .Max
        }
        assert(false)
        return .Add
    }

    _wgpu_blend_factor :: proc(blend_factor: Blend_Factor) -> wgpu.BlendFactor {
        switch blend_factor {
        case .Zero:                 return .Zero
        case .One:                  return .One
        case .Src_Color:            return .Src
        case .One_Minus_Src_Color:  return .OneMinusSrc
        case .Src_Alpha:            return .SrcAlpha
        case .One_Minus_Src_Alpha:  return .OneMinusSrcAlpha
        case .Dst_Alpha:            return .DstAlpha
        case .One_Minus_Dst_Alpha:  return .OneMinusDstAlpha
        case .Dst_Color:            return .Dst
        case .One_Minus_Dst_Color:  return .OneMinusDst
        case .Src_Alpha_Sat:        return .SrcAlphaSaturated
        }
        assert(false)
        return .One
    }

    _wgpu_cpu_access :: proc(usage: Usage) -> wgpu.BufferUsageFlags {
        switch usage {
        case .Dynamic:
            return {.MapWrite}
        case .Immutable, .Default:
            return {}
        }
        assert(false)
        return {}
    }

    _wgpu_index_format :: proc(format: Index_Format) -> wgpu.IndexFormat {
        switch format {
        case .Invalid:  return .Undefined
        case .U16: return .Uint16
        case .U32: return .Uint32
        }
        assert(false)
        return .Uint32
    }

    _wgpu_texture_bounds :: proc(bounds: Texture_Bounds) -> wgpu.AddressMode {
        switch bounds {
        case .Wrap:         return .Repeat
        case .Mirror:       return .MirrorRepeat
        case .Clamp:        return .ClampToEdge
        }
        assert(false)
        return .Repeat
    }

    _wgpu_topology :: proc(topology: Topology) -> wgpu.PrimitiveTopology {
        switch topology {
        case .Invalid:      return .Undefined
        case .Lines:        return .LineList
        case .Triangles:    return .TriangleList
        }
        assert(false)
        return .TriangleList
    }

    _wgpu_fill_mode :: proc(fill_mode: Fill_Mode) -> wgpu.PolygonMode {
        switch fill_mode {
        case .Invalid:      return .Fill
        case .Solid:        return .Fill
        case .Wireframe:    return .Line
        }
        assert(false)
        return wgpu.PolygonMode.Fill
    }

    _wgpu_cull_mode :: proc(cull_mode: Cull_Mode) -> wgpu.CullMode {
        switch cull_mode {
        case .Invalid:  return .Undefined
        case .None:     return .None
        case .Front:    return .Front
        case .Back:     return .Back
        }
        assert(false)
        return wgpu.CullMode.None
    }

    _wgpu_comparison :: proc(op: Comparison_Op) -> wgpu.CompareFunction {
        switch op {
        case .Never:         return .Never
        case .Less:          return .Less
        case .Equal:         return .Equal
        case .Less_Equal:    return .LessEqual
        case .Greater:       return .Greater
        case .Not_Equal:     return .NotEqual
        case .Greater_Equal: return .GreaterEqual
        case .Always:        return .Always
        }
        assert(false)
        return wgpu.CompareFunction.Always
    }

    _wgpu_texture_format :: proc(format: Texture_Format) -> wgpu.TextureFormat {
        switch format {
        case .Invalid:              return .Undefined
        case .Swapchain:            return .BGRA8Unorm
        case .RGBA_F32:             return .RGBA32Float
        case .RGBA_U32:             return .RGBA32Uint
        case .RGBA_S32:             return .RGBA32Sint
        case .RGBA_F16:             return .RGBA16Float
        case .RGBA_U16_Norm:        return .RGBA16Unorm
        case .RGBA_U16:             return .RGBA16Uint
        case .RGBA_S16_Norm:        return .RGBA16Snorm
        case .RGBA_S16:             return .RGBA16Sint
        case .RG_F32:               return .RG32Float
        case .RG_U32:               return .RG32Uint
        case .RG_S32:               return .RG32Sint
        case .RG_U10_A_U2_Norm:     return .RGB10A2Unorm
        case .RG_U10_A_U2:          return .RGB10A2Uint
        case .RG_F11_B_F10:         return .RG11B10Ufloat
        case .RGBA_U8_Norm:         return .RGBA8Unorm
        case .RGBA_U8:              return .RGBA8Uint
        case .RGBA_S8_Norm:         return .RGBA8Snorm
        case .RGBA_S8:              return .RGBA8Sint
        case .RG_F16:               return .RG16Float
        case .RG_U16_Norm:          return .RG16Unorm
        case .RG_U16:               return .RG16Uint
        case .RG_S16_Norm:          return .RG16Snorm
        case .RG_S16:               return .RG16Sint
        case .R_F32:                return .R32Float
        case .R_U32:                return .R32Uint
        case .R_S32:                return .R32Sint
        case .RG_U8_Norm:           return .RG8Unorm
        case .RG_U8:                return .RG8Uint
        case .RG_S8_Norm:           return .RG8Snorm
        case .RG_S8:                return .RG8Sint
        case .R_F16:                return .R16Float
        case .R_U16_Norm:           return .R16Unorm
        case .R_U16:                return .R16Uint
        case .R_S16_Norm:           return .R16Snorm
        case .R_S16:                return .R16Sint
        case .R_U8_Norm:            return .R8Unorm
        case .R_U8:                 return .R8Uint
        case .R_S8_Norm:            return .R8Snorm
        case .R_S8:                 return .R8Sint
        case .Depth_F32:            return .Depth32Float
        case .Depth_U24_Norm_S_U8:  return .Depth24PlusStencil8
        case .Depth_U16_Norm:       return .Depth16Unorm
        }
        assert(false)
        return .RGBA8Unorm
    }

    _wgpu_vertex_format :: proc(format: Vertex_Format) -> wgpu.VertexFormat {
        switch format {
        case .Invalid:
            assert(false)
        case .U8:            return .Uint8
        case .U8x2:          return .Uint8x2
        case .U8x4:          return .Uint8x4
        case .I8:            return .Sint8
        case .I8x2:          return .Sint8x2
        case .I8x4:          return .Sint8x4
        case .U8_Norm:       return .Unorm8
        case .U8x2_Norm:     return .Unorm8x2
        case .U8x4_Norm:     return .Unorm8x4
        case .I8_Norm:       return .Snorm8
        case .I8x2_Norm:     return .Snorm8x2
        case .I8x4_Norm:     return .Snorm8x4
        case .U16:           return .Uint16
        case .U16x2:         return .Uint16x2
        case .U16x4:         return .Uint16x4
        case .I16:           return .Sint16
        case .I16x2:         return .Sint16x2
        case .I16x4:         return .Sint16x4
        case .U16_Norm:      return .Unorm16
        case .U16x2_Norm:    return .Unorm16x2
        case .U16x4_Norm:    return .Unorm16x4
        case .I16_Norm:      return .Snorm16
        case .I16x2_Norm:    return .Snorm16x2
        case .I16x4_Norm:    return .Snorm16x4
        case .F16:           return .Float16
        case .F16x2:         return .Float16x2
        case .F16x4:         return .Float16x4
        case .F32:           return .Float32
        case .F32x2:         return .Float32x2
        case .F32x3:         return .Float32x3
        case .F32x4:         return .Float32x4
        case .U32:           return .Uint32
        case .U32x2:         return .Uint32x2
        case .U32x3:         return .Uint32x3
        case .U32x4:         return .Uint32x4
        case .I32:           return .Sint32
        case .I32x2:         return .Sint32x2
        case .I32x3:         return .Sint32x3
        case .I32x4:         return .Sint32x4
        case .U10x3_U2_Norm: return .Unorm10_10_10_2
        }
        assert(false)
        return .Uint8
    }

}
