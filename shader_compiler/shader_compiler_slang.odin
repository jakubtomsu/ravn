#+vet explicit-allocators shadowing style
#+build !js
package ravn_shader_compiler

import "../base"
import "../platform"
import "slang"
import "base:runtime"

_Slang_State :: struct {
    using vtable:   slang.Global_VTable,
    initialized:    bool,
    module:         platform.Module,
    global_session: ^slang.IGlobalSession,
}

_slang_init :: proc() -> bool {
    if _state.slang.initialized {
        return true
    }

    module_ok: bool
    _state.module, module_ok = platform.load_module("slang.dll")
    if !module_ok {
        base.log_err("Failed to load slang.dll. Ensure it's in your working directory to compile shaders.")
        return false
    }

    _state.slang.vtable = {
        createBlob                           = auto_cast _load_sym("slang_createBlob") or_return,
        loadModuleFromSource                 = auto_cast _load_sym("slang_loadModuleFromSource") or_return,
        loadModuleFromIRBlob                 = auto_cast _load_sym("slang_loadModuleFromIRBlob") or_return,
        loadModuleInfoFromIRBlob             = auto_cast _load_sym("slang_loadModuleInfoFromIRBlob") or_return,
        createGlobalSession                  = auto_cast _load_sym("slang_createGlobalSession") or_return,
        createGlobalSession2                 = auto_cast _load_sym("slang_createGlobalSession2") or_return,
        createGlobalSessionWithoutCoreModule = auto_cast _load_sym("slang_createGlobalSessionWithoutCoreModule") or_return,
        shutdown                             = auto_cast _load_sym("slang_shutdown") or_return,
    }

    if !_slang_check(_state.slang.createGlobalSession(slang.API_VERSION, &_state.slang.global_session)) {
        return false
    }

    _state.slang.initialized = true

    return true

    _load_sym :: proc(name: cstring) -> (rawptr, bool) {
        result := platform.get_module_symbol_address(_state.module, name)
        if result == nil {
            base.log_err("Failed to find symbol '%s' in slang.dll", name)
            return nil, false
        }
        return result, true
    }
}

_compile_slang_wgsl :: proc(
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {

    if !_slang_init() {
        return {}, false
    }

    // Implements something like the following slangc command:
    // slangc.exe name.hlsl -target wgsl -entry vs_main -stage vertex -o shader.wgsl -fvk-b-shift 0 0 -fvk-t-shift 8 0 -fvk-s-shift 16 0

    target_desc := slang.TargetDesc{
        structureSize = size_of(slang.TargetDesc),
        format = .WGSL,
        profile = _state.slang.global_session->findProfile("wgsl_1_0"),
    }

    // Hardcoded for now...

    CONSTANTS_BIND_SLOTS :: 8
    SAMPLER_BIND_SLOTS :: 8
    RESOURCE_BIND_SLOTS :: 32
    RW_RESOURCE_BIND_SLOTS :: 32

    SAMPLER_SLOT_SHIFT :: 0
    CONSTANTS_SLOT_SHIFT :: SAMPLER_SLOT_SHIFT + SAMPLER_BIND_SLOTS
    RESOURCE_SLOT_SHIFT :: CONSTANTS_SLOT_SHIFT + CONSTANTS_BIND_SLOTS
    RW_RESOURCE_SLOT_SHIFT :: RESOURCE_SLOT_SHIFT + RESOURCE_BIND_SLOTS


    // NOTE: this is broken
    // https://github.com/shader-slang/slang/issues/10441
    options := [?]slang.CompilerOptionEntry {
        { .Stage, {.Int, i32(slang.Stage.VERTEX), 0, nil, nil}},
        { .Optimization, {.Int, i32(opts.release ? slang.OptimizationLevel.HIGH : slang.OptimizationLevel.NONE), 0, nil, nil}},
        // { .VulkanBindShift, {.Int, pack_vk_shift(slang.HLSLToVulkanLayoutBindingKind.Sampler, 0), SAMPLER_SLOT_SHIFT, nil, nil}},
        // { .VulkanBindShift, {.Int, pack_vk_shift(slang.HLSLToVulkanLayoutBindingKind.ConstantBuffer, 0), CONSTANTS_SLOT_SHIFT, nil, nil}},
        // { .VulkanBindShift, {.Int, pack_vk_shift(slang.HLSLToVulkanLayoutBindingKind.ShaderResource, 0), RESOURCE_SLOT_SHIFT, nil, nil}},
        // { .VulkanBindShift, {.Int, pack_vk_shift(slang.HLSLToVulkanLayoutBindingKind.UnorderedAccess, 0), RW_RESOURCE_SLOT_SHIFT, nil, nil}},
    }

    file_system: _Slang_IFileSystem = {
        ifilesystem = {
            vtable = &slang.IFileSystem_VTable{
                icastable_vtable = {
                    iunknown_vtable = {
                        queryinterface = _slang_ifilesystem_queryinterface,
                        addRef = _slang_ifilesystem_addref,
                        release = _slang_ifilesystem_release,
                    },
                    castAs = _slang_ifilesystem_castas,
                },
                loadFile = _slang_ifilesystem_loadfile,
            },
        },
        ctx = context,
        opts = opts,
    }

    session_desc := slang.SessionDesc{
        structureSize = size_of(slang.SessionDesc),
        targetCount = 1,
        targets = &target_desc,
        defaultMatrixLayoutMode = .COLUMN_MAJOR,
        compilerOptionEntries = &options[0],
        compilerOptionEntryCount = len(options),
        fileSystem = &file_system,
    }

    session: ^slang.ISession
    _slang_check(_state.slang.global_session->createSession(session_desc, &session))

    cname := clone_to_cstring(name, context.temp_allocator)

    source_blob := _state.slang.createBlob(raw_data(source), len(source))
    diag: ^slang.IBlob
    module := session->loadModuleFromSource(cname, cname, source_blob, &diag)

    _slang_diag(diag)
    if module == nil {
        return nil, false
    }

    entry_point_name: cstring
    switch opts.stage {
    case .Invalid:
        assert(false)
        return {}, false
    case .Vertex: entry_point_name = "vs_main"
    case .Pixel:  entry_point_name = "ps_main"
    case .Compute:entry_point_name = "cs_main"
    }

    entry_point: ^slang.IEntryPoint
    _slang_check(module->findAndCheckEntryPoint(entry_point_name, _slang_stage(opts.stage), &entry_point, &diag))
    _slang_diag(diag)

    components := [?]^slang.IComponentType{module, entry_point}
    composite: ^slang.IComponentType
    _slang_check(session->createCompositeComponentType(&components[0], len(components), &composite, &diag))

    _slang_diag(diag)
    if composite == nil {
        return nil, false
    }

    wgsl_code: ^slang.IBlob
    _slang_check(composite->getEntryPointCode(0, 0, &wgsl_code, &diag))

    _slang_diag(diag)
    if wgsl_code == nil {
        return nil, false
    }

    return _slang_blob_buf(wgsl_code), true

    pack_vk_shift :: proc(#any_int kind: u8, set: u32) -> i32 {
        return transmute(i32)((u32(kind) << 24) | (set & 0x00FFFFFF))
    }
}

_slang_check :: proc(res: slang.Result, expr := #caller_expression(res), loc := #caller_location) -> bool {
    if res != .OK {
        base.log_err("%v (%x)", res, transmute(u32)res, loc = loc)
        assert(false, message = expr, loc = loc)
        return false
    }
    return true
}

_slang_diag :: proc(diag: ^slang.IBlob, loc := #caller_location) {
    if diag != nil {
        base.log_err("Slang Error: %s", _slang_blob_str(diag), loc = loc)
    }
}

_slang_blob_buf :: proc(blob: ^slang.IBlob) -> []byte {
    return (cast([^]byte)blob->getBufferPointer())[:blob->getBufferSize()]
}

_slang_blob_str :: proc(blob: ^slang.IBlob) -> string {
    return transmute(string)_slang_blob_buf(blob)
}

_slang_stage :: proc(stage: Stage) -> slang.Stage {
    switch stage {
    case: fallthrough
    case .Invalid: return .NONE
    case .Vertex: return .VERTEX
    case .Pixel: return .PIXEL
    case .Compute: return .COMPUTE
    }
}

_Slang_IFileSystem :: struct {
    #subtype ifilesystem: slang.IFileSystem,
    ctx:    runtime.Context,
    opts:   Options,
}

_slang_ifilesystem_loadfile :: proc "system" (
    _this:      ^slang.IFileSystem,
    path:       cstring,
    outBlob:    ^^slang.IBlob,
) -> slang.Result {
    assert_contextless(_this != nil)

    this := cast(^_Slang_IFileSystem)_this
    context = this.ctx

    assert(path != nil)
    assert(outBlob != nil)

    // base.log_info("INCLUDE %s", path)

    if this.opts.include_proc == nil {
        return .E_NOT_FOUND
    }

    result, ok := this.opts.include_proc(
        path = string(path),
        user = this.opts.user,
    )

    if !ok {
        return .E_NOT_FOUND
    }

    outBlob^ = _state.slang.createBlob(raw_data(result), len(result))
    return .OK
}

_slang_ifilesystem_castas :: proc "system" (this: ^slang.ICastable, #by_ptr guid: slang.UUID) -> rawptr {
    switch guid {
    case slang.IUnknown_UUID, slang.ICastable_UUID, slang.IFileSystem_UUID:
        return rawptr(this)
    }
    return nil
}

_slang_ifilesystem_queryinterface :: proc "system" (this: ^slang.IUnknown, #by_ptr uuid: slang.UUID, outObject: ^rawptr) -> slang.Result {
    switch uuid {
    case slang.IUnknown_UUID, slang.ICastable_UUID, slang.IFileSystem_UUID:
        outObject^ = this
        return .OK
    }
    return .FAIL
}

_slang_ifilesystem_addref :: proc "system" (this: ^slang.IUnknown) -> u32 {
    return 1
}

_slang_ifilesystem_release :: proc "system" (this: ^slang.IUnknown) -> u32 {
    return 1
}
