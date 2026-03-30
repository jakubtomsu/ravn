package raven_gpu

import "../base"
import "vendor:wgpu"
import "base:runtime"
import "base:intrinsics"

_ :: wgpu
_ :: runtime
_ :: intrinsics

when BACKEND == BACKEND_WGPU {

    _WGPU_CALLBACK_MODE: wgpu.CallbackMode: .AllowProcessEvents

    _BIND_GROUP_CACHE_SIZE :: 512
    _SAMPLER_CACHE_BUCKET :: 8
    _DRAW_DATA_BUFFER_SIZE :: 1024 * 64

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

        bind_group_hash:        [_BIND_GROUP_CACHE_SIZE]Hash,
        bind_group_data:        [_BIND_GROUP_CACHE_SIZE]_Bind_Group,
        uniform_offset_align:   u32,

        // filter, bounds x
        sampler_cache:          [Filter][Texture_Bounds]Bucket(_SAMPLER_CACHE_BUCKET, Sampler_Desc, _Sampler),
    }

    _Bind_Group_Handle :: Handle // currently gen unused

    _Pipeline :: struct {
        pip:        wgpu.RenderPipeline,
        bind_group: _Bind_Group_Handle,
    }

    _Compute_Pipeline :: struct {
        pip:        wgpu.ComputePipeline,
        bind_group: _Bind_Group_Handle,
    }

    _Shader :: struct {
        module: wgpu.ShaderModule,
    }

    _Blend :: struct {
        blend: wgpu.BlendState,
    }

    _Resource :: struct #raw_union {
        buf:    wgpu.Buffer,
        using _: struct {
            tex:        wgpu.Texture,
            tex_view:   wgpu.TextureView,
        },
    }

    _Sampler :: struct {
        smp:    wgpu.Sampler,
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

        case .Timeout, .Outdated, .Lost:
            base.log_info("%v", _state.surface_texture.status)
            // Skip this frame, and re-configure surface.
            if _state.surface_texture.texture != nil {
                wgpu.TextureRelease(_state.surface_texture.texture)
            }
            return false

        case .OutOfMemory, .DeviceLost, .Error:
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

    _Bind_Group :: struct {
        layout: wgpu.BindGroupLayout,
        group:  wgpu.BindGroup,
    }


    _get_or_create_sampler :: proc(desc: Sampler_Desc) -> (result: _Sampler) {
        bucket := &_state.sampler_cache[desc.filter][desc.bounds.x]
        sampler := bucket_find_or_create(bucket, desc, _create_sampler)
        return sampler
    }

    _create_sampler :: proc(desc: Sampler_Desc) -> (result: _Sampler) {
        base.log_debug("GPU: Creating WebGPU sampler")

        min_filter, mag_filter, mip_filter := _wgpu_filter(desc.filter)

        result.smp = wgpu.DeviceCreateSampler(_state.device, &wgpu.SamplerDescriptor{
            label = "<SMP>",
            addressModeU = _wgpu_texture_bounds(desc.bounds.x),
            addressModeV = _wgpu_texture_bounds(desc.bounds.y),
            addressModeW = _wgpu_texture_bounds(desc.bounds.z),
            magFilter = mag_filter,
            minFilter = min_filter,
            mipmapFilter = mip_filter,
            lodMinClamp = desc.mip_min,
            lodMaxClamp = desc.mip_max,
            // compare = _wgpu_comparison(desc.comparison),
            compare = .Undefined,
            maxAnisotropy = clamp(u16(desc.max_aniso), 1, 16),
        })

        return result
    }

    _get_or_create_bind_group :: proc(desc: Pipeline_Bindings_Desc) -> (result: _Bind_Group, handle: _Bind_Group_Handle, ok: bool) {
        hash := hash_pipeline_bindings_desc(desc)
        index, prev := _table_find_empty_hash(&_state.bind_group_hash, hash) or_return

        // Already exists
        if prev != 0 {
            return _state.bind_group_data[index], {index = Handle_Index(index), gen = 0}, true
        }

        result = _create_bind_group(desc) or_return

        _state.bind_group_data[index] = result
        _state.bind_group_hash[index] = hash

        return result, {index = Handle_Index(index), gen = 0}, true
    }

    _create_bind_group :: proc(desc: Pipeline_Bindings_Desc) -> (result: _Bind_Group, ok: bool) {
        base.log_debug("GPU: Creating WebGPU bind group")

        num_entries := 0
        layout_entries: [SAMPLER_BIND_SLOTS + CONSTANTS_BIND_SLOTS + RESOURCE_BIND_SLOTS]wgpu.BindGroupLayoutEntry
        group_entries:  [SAMPLER_BIND_SLOTS + CONSTANTS_BIND_SLOTS + RESOURCE_BIND_SLOTS]wgpu.BindGroupEntry

        for smp, i in desc.samplers {
            sampler := _get_or_create_sampler(smp)

            binding := u32(SAMPLER_SLOT_SHIFT + i)

            layout_entries[num_entries] = wgpu.BindGroupLayoutEntry{
                binding = binding,
                visibility = wgpu.ShaderStageFlags{.Vertex, .Fragment, .Compute},
                sampler = wgpu.SamplerBindingLayout{
                    // NOTE: must use loads, not samples for non-filterable textures.
                    type = .Filtering,
                },
            }

            group_entries[num_entries] = wgpu.BindGroupEntry{
                binding = binding,
                sampler = sampler.smp,
            }

            num_entries += 1
        }

        for handle, i in desc.constants {
            res := get_internal_resource(handle) or_continue

            assert(res.kind == .Constants)

            binding := u32(CONSTANTS_SLOT_SHIFT + i)

            layout_entries[num_entries] = wgpu.BindGroupLayoutEntry{
                binding = binding,
                visibility = wgpu.ShaderStageFlags{.Vertex, .Fragment, .Compute},
                buffer = wgpu.BufferBindingLayout{
                    type = wgpu.BufferBindingType.Uniform,
                    hasDynamicOffset = res.size.y > 1,
                    minBindingSize = 0,
                },
            }

            group_entries[num_entries] = wgpu.BindGroupEntry{
                binding = binding,
                buffer = res.buf,
                offset = 0,
                size = u64(res.size.x),
            }

            num_entries += 1
        }

        for handle, i in desc.resources {
            res := get_internal_resource(handle) or_continue

            binding := u32(RESOURCE_SLOT_SHIFT + i)

            layout_entries[num_entries] = wgpu.BindGroupLayoutEntry{
                binding = binding,
                visibility = wgpu.ShaderStageFlags{.Vertex, .Fragment, .Compute},
            }

            group_entries[num_entries] = wgpu.BindGroupEntry{
                binding = binding,
            }

            switch res.kind {
            case .Invalid, .Constants, .Index_Buffer, .Swapchain:
                assert(false)

            case .Buffer:
                layout_entries[num_entries].buffer = wgpu.BufferBindingLayout{
                    type = .ReadOnlyStorage,
                    hasDynamicOffset = false,
                    minBindingSize = 0,
                }

                assert(res.size.x % 4 == 0)

                group_entries[num_entries].size = u64(res.size.x)
                group_entries[num_entries].buffer = res.buf

            case .Texture2D, .Texture3D:
                dim: wgpu.TextureViewDimension

                if res.kind == .Texture3D {
                    dim = ._3D
                } else if res.size.z > 1 {
                    dim = ._2DArray
                } else {
                    dim = ._2DArray
                }

                layout_entries[num_entries].texture = wgpu.TextureBindingLayout{
                    // TODO: handle other sample types
                    sampleType = wgpu.TextureSampleType.Float,
                    viewDimension = dim,
                    multisampled = false,
                }

                group_entries[num_entries].textureView = res.tex_view
            }

            num_entries += 1
        }

        for handle, i in desc.rw_resources {
            res := get_internal_resource(handle) or_continue

            binding := u32(RW_RESOURCE_SLOT_SHIFT + i)

            layout_entries[num_entries] = wgpu.BindGroupLayoutEntry{
                binding = binding,
                visibility = wgpu.ShaderStageFlags{.Compute}, // NOTE: Compute only RW resources for now
            }

            group_entries[num_entries] = wgpu.BindGroupEntry{
                binding = binding,
            }

            switch res.kind {
            case .Invalid, .Constants, .Index_Buffer, .Swapchain:
                assert(false)

            case .Buffer:
                layout_entries[num_entries].buffer = wgpu.BufferBindingLayout{
                    type = .Storage,
                    hasDynamicOffset = false,
                    minBindingSize = 0,
                }

                assert(res.size.x % 4 == 0)

                group_entries[num_entries].size = u64(res.size.x)
                group_entries[num_entries].buffer = res.buf

            case .Texture2D, .Texture3D:
                dim: wgpu.TextureViewDimension

                if res.kind == .Texture3D {
                    dim = ._3D
                } else if res.size.z > 1 {
                    dim = ._2DArray
                } else {
                    dim = ._2DArray
                }

                layout_entries[num_entries].storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadWrite,
                    format = _wgpu_texture_format(res.format),
                    viewDimension = dim,
                }

                group_entries[num_entries].textureView = res.tex_view
            }

            num_entries += 1
        }

        if true {
            for item, _ in layout_entries[:num_entries] {
                kind: string = "???"

                if item.buffer != {} {
                    kind = "Buffer"
                } else if item.sampler != {} {
                    kind = "Sampler"
                } else if item.texture != {} {
                    kind = item.texture.viewDimension == ._2DArray ? "TextureArray" : "Texture"
                } else if item.storageTexture != {} {
                    kind = "StorageTexture"
                }

                // base.log_debug("Layout item #%i: {} binding %i", i, kind, item.binding)
            }
        }

        result.layout = wgpu.DeviceCreateBindGroupLayout(_state.device, &wgpu.BindGroupLayoutDescriptor{
            label = "<BIND GROUP LAYOUT>",
            entryCount = uint(num_entries),
            entries = &layout_entries[0],
        })

        if result.layout == nil {
            base.log_err("WGPU: Failed to create bind group layout")
            return {}, false
        }

        result.group = wgpu.DeviceCreateBindGroup(_state.device, &wgpu.BindGroupDescriptor{
            label = "<BIND GROUP>",
            layout = result.layout,
            entryCount = uint(num_entries),
            entries = &group_entries[0],
        })

        if result.group == nil {
            base.log_err("WGPU: Failed to create bind group")
            return {}, false
        }

        return result, true
    }

    _create_pipeline :: proc(name: string, desc: Pipeline_Desc) -> (result: _Pipeline, ok: bool) {
        // base.log_debug("GPU: Creating WebGPU pipeline '%s'", name)

        bindings := get_pipeline_desc_bindings(desc)
        bind_group, bind_group_handle, bind_group_ok := _get_or_create_bind_group(bindings)
        if !bind_group_ok {
            base.log_err("WGPU: Failed to create pipeline: bind group creation failed")
            return {}, false
        }

        pip_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
            label = name,
            bindGroupLayoutCount = 1,
            bindGroupLayouts = &bind_group.layout,
        })

        if pip_layout == nil {
            base.log_err("WGPU: Failed to create pipeline layout")
            return {}, false
        }

        // NOTE: fill mode is ignored.

        ps, ps_ok := get_internal_shader(desc.ps)
        vs, vs_ok := get_internal_shader(desc.vs)

        assert(ps_ok)
        assert(vs_ok)
        assert(ps.kind == .Pixel)
        assert(vs.kind == .Vertex)

        color_targets_num := 0
        color_targets: [RENDER_TEXTURE_BIND_SLOTS]wgpu.ColorTargetState

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

        result.pip = wgpu.DeviceCreateRenderPipeline(_state.device, &{
            label = name,
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
                bufferCount = 0,
                buffers = nil,
            },
            fragment = &wgpu.FragmentState{
                module = ps.module,
                entryPoint = "ps_main",
                constantCount = 0,
                constants = nil,
                targetCount = 1, // len(color_targets),
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

        assert(bind_group_handle != {})
        assert(bind_group.group != nil)

        result.bind_group = bind_group_handle

        return result, true
    }

    _create_compute_pipeline :: proc(name: string, desc: Compute_Pipeline_Desc) -> (result: _Compute_Pipeline, ok: bool) {
        bind_group, bind_group_handle, bind_group_ok := _get_or_create_bind_group(desc.bindings)
        if !bind_group_ok {
            base.log_err("WGPU: Failed to create pipeline: bind group creation failed")
            return {}, false
        }

        pip_layout := wgpu.DeviceCreatePipelineLayout(_state.device, &wgpu.PipelineLayoutDescriptor{
            label = name,
            bindGroupLayoutCount = 1,
            bindGroupLayouts = &bind_group.layout,
        })

        if pip_layout == nil {
            base.log_err("WGPU: Failed to create pipeline layout")
            return {}, false
        }

        cs, cs_ok := get_internal_shader(desc.cs)
        assert(cs_ok)

        result.pip = wgpu.DeviceCreateComputePipeline(
            _state.device,
            &wgpu.ComputePipelineDescriptor{
                label = name,
                layout = nil,
                compute = wgpu.ProgrammableStageDescriptor{
                    module = cs.module,
                    entryPoint = "cs_main",
                    constants = nil,
                    constantCount = 0,
                },
            },
        )

        return {}, true
    }

    _update_swapchain :: proc(_: ^_Resource, _: rawptr, size: [2]i32) -> (ok: bool) {
        _state.config = wgpu.SurfaceConfiguration {
            device      = _state.device,
            usage       = { .RenderAttachment },
            // format      = .BGRA8Unorm,
            format      = .RGBA8Unorm,
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

    _create_constants :: proc(
        name:       string,
        item_size:  i32,
        item_num:   i32,
    ) -> (result: _Resource, ok: bool) {

        size: u64
        if item_num > 1 {
            size = u64(runtime.align_forward_int(int(item_size), int(_state.uniform_offset_align))) * u64(item_num)
        } else {
            size = u64(item_size) * u64(item_num)
        }

        result.buf = wgpu.DeviceCreateBuffer(_state.device, &wgpu.BufferDescriptor{
            label = name,
            usage = {.Uniform, .CopyDst},
            size = size,
            mappedAtCreation = false,
        })

        if result.buf == nil {
            return {}, false
        }

        return result, true
    }

    _create_shader :: proc(name: string, data: []u8, kind: Shader_Kind) -> (result: _Shader, ok: bool) {
        result.module = wgpu.DeviceCreateShaderModule(_state.device, &wgpu.ShaderModuleDescriptor{
            nextInChain = &wgpu.ShaderSourceWGSL{
                sType = .ShaderSourceWGSL,
                code  = string(data),
            },
            label = name,
        })

        if result.module == nil {
            return {}, false
        }

        return result, true
    }

    _create_texture_2d :: proc(
        name: string,
        format: Texture_Format,
        size: [2]i32,
        usage: Usage,
        mips: i32,
        array_depth: i32,
        render_texture: bool,
        rw_resource: bool,
        data: []byte,
    ) -> (result: _Resource, ok: bool) {
        usage: wgpu.TextureUsageFlags = {.TextureBinding}

        if render_texture {
            usage += {.RenderAttachment}
        } else {
            usage += {.CopyDst}
        }

        formats := [?]wgpu.TextureFormat{
            _wgpu_texture_format(format),
        }

        tex_desc := wgpu.TextureDescriptor{
            label = name,
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

        row_bytes := u32(texture_pixel_size(format) * size.x)

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
	        label = name,
	        format = formats[0],
	        dimension = ._2DArray,
	        baseMipLevel = 0,
	        mipLevelCount = u32(mips),
	        baseArrayLayer = 0,
	        arrayLayerCount = u32(array_depth),
	        aspect = wgpu.TextureAspect.All, // tf is this
	        usage = usage,
        })

        if result.tex == nil {
            return {}, false
        }

        return result, true
    }

    _create_buffer :: proc(
        name:   string,
        stride: i32,
        size:   i32,
        usage:  Usage,
        data:   []u8,
    ) -> (result: _Resource, ok: bool) {
        result.buf = wgpu.DeviceCreateBuffer(_state.device, &{
            label            = name,
            usage            = _wgpu_buffer_usage(usage) + {.Storage},
            size             = u64(size),
            mappedAtCreation = data != nil,
        })

        if result.buf == nil {
            return {}, false
        }

        if data != nil {
            mapping := wgpu.RawBufferGetMappedRange(result.buf, offset = 0, size = len(data))
            intrinsics.mem_copy_non_overlapping(mapping, raw_data(data), len(data))

            wgpu.BufferUnmap(result.buf)
        }

        return result, true
    }

    _create_index_buffer :: proc(
        name:   string,
        size:   i32,
        data:   []u8,
        usage:  Usage,
    ) -> (result: _Resource, ok: bool) {
        result.buf = wgpu.DeviceCreateBuffer(_state.device, &{
            label            = name,
            usage            = _wgpu_buffer_usage(usage) + {.Index},
            size             = u64(size),
            mappedAtCreation = data != nil,
        })

        if result.buf == nil {
            return {}, false
        }

        if data != nil {
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

    _destroy_resource :: proc(resource: Resource_State) {
        switch resource.kind {
        case .Invalid, .Swapchain:
            assert(false)

        case .Buffer, .Constants, .Index_Buffer:
            wgpu.BufferDestroy(resource.buf)

        case .Texture2D, .Texture3D:
            wgpu.TextureDestroy(resource.tex)
        }
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: Actions
    //

    _begin_pass :: proc(name: string, desc: Pass_Desc) {
        assert(_state.render_pass_encoder == nil)

        // TODO
        num_color_atts := 0
        color_atts: [RENDER_TEXTURE_BIND_SLOTS]wgpu.RenderPassColorAttachment

        for color, i in desc.colors {
            res := get_internal_resource(color.resource) or_break

            num_color_atts += 1

            view: wgpu.TextureView
            #partial switch res.kind {
            case .Texture2D:
                view = res.tex_view

            case .Swapchain:
                view = _state.surface_view

            case:
                base.log_err("Invalid pass color, must be a Texture2D")
            }

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
        if res, res_ok := get_internal_resource(desc.depth.resource); res_ok {
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
                label = name,
                colorAttachmentCount = uint(num_color_atts),
                colorAttachments = &color_atts[0],
                depthStencilAttachment = depth_stencil,
            },
        )
    }

    _end_pass :: proc() {
        assert(_state.render_pass_encoder != nil)
        wgpu.RenderPassEncoderEnd(_state.render_pass_encoder)
        _state.render_pass_encoder = nil
    }

    _bind_pipeline :: proc(
        curr_pip: Pipeline_State,
        curr: Pipeline_Desc,
        prev: Pipeline_Desc,
    ) {
        assert(curr_pip.pip != nil)
        assert(_state.render_pass_encoder != nil)
        if res, res_ok := get_internal_resource(curr.index.resource); res_ok {
            wgpu.RenderPassEncoderSetIndexBuffer(
                _state.render_pass_encoder,
                buffer = res.buf,
                format = _wgpu_index_format(curr.index.format),
                offset = u64(curr.index.offset),
                size = u64(res.size.x),
            )
        }
        wgpu.RenderPassEncoderSetPipeline(_state.render_pass_encoder, curr_pip.pip)
    }

    _begin_compute_pass :: proc(name: string) {
        assert(_state.compute_pass_encoder == nil)
        _state.compute_pass_encoder = wgpu.CommandEncoderBeginComputePass(
            _state.command_encoder,
            &wgpu.ComputePassDescriptor{
                label = name,
            },
        )
    }

    _end_compute_pass :: proc() {
        assert(_state.compute_pass_encoder != nil)
        wgpu.ComputePassEncoderEnd(_state.compute_pass_encoder)
        _state.compute_pass_encoder = nil
    }

    _bind_compute_pipeline :: proc(
        curr_pip:   Compute_Pipeline_State,
        curr:       Compute_Pipeline_Desc,
        prev:       Compute_Pipeline_Desc,
    ) {
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

            assert(len(data) % int(res.size.x) == 0)

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

    _update_texture_2d :: proc(res: Resource_State, data: []byte, slice: i32) {
        assert(res.format != .Invalid)

        row_bytes := u32(texture_pixel_size(res.format) * res.size.x)

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

    _bind_constants_items :: proc(offsets: []u32) {
        curr_pip, curr_pip_ok := get_internal_pipeline(_state.curr_pipeline)

        assert(curr_pip_ok)
        assert(_state.bind_group_hash[curr_pip.bind_group.index] != 0)

        bind_group := _state.bind_group_data[curr_pip.bind_group.index]

        assert(bind_group.group != nil)

        offsets_len := 0
        offsets_buf: [CONSTANTS_BIND_SLOTS]u32

        // TODO: some of this should be cached on bind_pipeline
        for offset, i in offsets {

            handle := _state.curr_pipeline_desc.constants[i]

            res := get_internal_resource(handle) or_continue

            assert(res.kind == .Constants)

            if res.size.y == 1 {
                continue
            }

            aligned_size := u32(runtime.align_forward_int(int(res.size.x), int(_state.uniform_offset_align)))

            offsets_buf[offsets_len] = offset * aligned_size
            offsets_len += 1
        }

        wgpu.RenderPassEncoderSetBindGroup(
            _state.render_pass_encoder,
            groupIndex = 0,
            group = bind_group.group,
            dynamicOffsets = offsets_buf[:offsets_len],
        )
    }

    _draw_non_indexed :: proc(
        vertex_num:     u32,
        instance_num:   u32,
        const_offsets:  []u32,
    ) {
        assert(_state.curr_pipeline != {})

        _bind_constants_items(const_offsets)

        wgpu.RenderPassEncoderDraw(
            _state.render_pass_encoder,
            vertexCount = vertex_num,
            instanceCount = instance_num,
            firstVertex = 0,
            firstInstance = 0,
        )
    }

    _draw_indexed :: proc(
        index_num:      u32,
        instance_num:   u32,
        index_offset:   u32,
        const_offsets:  []u32,
    ) {
        _bind_constants_items(const_offsets)

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

        base.log(
            wgpu.ConvertWGPUToOdinLogLevel(level),
            "WGPU: %s",
            msg,
        )
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

    _wgpu_filter :: proc(filter: Filter) -> (min: wgpu.FilterMode, mag: wgpu.FilterMode, mip: wgpu.MipmapFilterMode) {
        switch filter {
        case .Unfiltered:       return .Nearest, .Nearest, .Nearest
        case .Mip_Filtered:     return .Nearest, .Nearest, .Linear
        case .Mag_Filtered:     return .Nearest, .Linear,  .Nearest
        case .Mag_Mip_Filtered: return .Nearest, .Linear,  .Linear
        case .Min_Filtered:     return .Linear,  .Nearest, .Nearest
        case .Min_Mip_Filtered: return .Linear,  .Nearest, .Linear
        case .Min_Mag_Filtered: return .Linear,  .Linear,  .Nearest
        case .Filtered:         return .Linear,  .Linear,  .Linear
        }
        assert(false)
        return .Nearest, .Nearest, .Nearest
    }

    _wgpu_texture_format :: proc(format: Texture_Format) -> wgpu.TextureFormat {
        switch format {
        case .Invalid:          return .Undefined
        case .RGBA_F32:         return .RGBA32Float
        case .RGBA_U32:         return .RGBA32Uint
        case .RGBA_S32:         return .RGBA32Sint
        case .RGBA_F16:         return .RGBA16Float
        case .RGBA_U16_Norm:    return .Rgba16Unorm
        case .RGBA_U16:         return .RGBA16Uint
        case .RGBA_S16_Norm:    return .Rgba16Snorm
        case .RGBA_S16:         return .RGBA16Sint
        case .RG_F32:           return .RG32Float
        case .RG_U32:           return .RG32Uint
        case .RG_S32:           return .RG32Sint
        case .RG_U10_A_U2_Norm: return .RGB10A2Unorm
        case .RG_U10_A_U2:      return .RGB10A2Uint
        case .RG_F11_B_F10:     return .RG11B10Ufloat
        case .RGBA_U8_Norm:     return .RGBA8Unorm
        case .RGBA_U8:          return .RGBA8Uint
        case .RGBA_S8_Norm:     return .RGBA8Snorm
        case .RGBA_S8:          return .RGBA8Sint
        case .RG_F16:           return .RG16Float
        case .RG_U16_Norm:      return .Rg16Unorm
        case .RG_U16:           return .RG16Uint
        case .RG_S16_Norm:      return .Rg16Snorm
        case .RG_S16:           return .RG16Sint
        case .D_F32:            return .Depth32Float
        case .R_F32:            return .R32Float
        case .R_U32:            return .R32Uint
        case .R_S32:            return .R32Sint
        case .D_U24_Norm_S_U8:  return .Depth24PlusStencil8
        case .RG_U8_Norm:       return .RG8Unorm
        case .RG_U8:            return .RG8Uint
        case .RG_S8_Norm:       return .RG8Snorm
        case .RG_S8:            return .RG8Sint
        case .R_F16:            return .R16Float
        case .D_U16_Norm:       return .Depth16Unorm
        case .R_U16_Norm:       return .R16Unorm
        case .R_U16:            return .R16Uint
        case .R_S16_Norm:       return .R16Snorm
        case .R_S16:            return .R16Sint
        case .R_U8_Norm:        return .R8Unorm
        case .R_U8:             return .R8Uint
        case .R_S8_Norm:        return .R8Snorm
        case .R_S8:             return .R8Sint
        }
        assert(false)
        return .RGBA8Unorm
    }

}
