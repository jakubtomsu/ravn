#+vet explicit-allocators shadowing style
#+build windows
package raven_shader_compiler

import "../base"

import "base:runtime"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/d3d_compiler"

_compile_dxbc :: proc(
    name:           string,
    source:         string,
    opts:           Options,
) -> (result: []byte, ok: bool) {
    entry_point_name: cstring
    target_name: cstring

    switch opts.stage {
    case .Invalid:
        assert(false)
        return {}, false

    case .Vertex:
        entry_point_name = "vs_main"
        target_name = "vs_5_0"

    case .Pixel:
        entry_point_name = "ps_main"
        target_name = "ps_5_0"

    case .Compute:
        entry_point_name = "cs_main"
        target_name = "cs_5_0"
    }

    flags: d3d_compiler.D3DCOMPILE
    if opts.release {
        flags = {
            .PACK_MATRIX_COLUMN_MAJOR,
            .OPTIMIZATION_LEVEL3,
        }
    } else {
        flags = {
            .DEBUG,
            .SKIP_OPTIMIZATION,
            .PACK_MATRIX_COLUMN_MAJOR,
            .ENABLE_STRICTNESS,
            .WARNINGS_ARE_ERRORS,
            .ALL_RESOURCES_BOUND,
        }
    }

    defs, defs_err := runtime.make_multi_pointer([^]d3d_compiler.SHADER_MACRO, len(opts.defines) + 1, context.temp_allocator) // null termination
    assert(defs_err == nil)

    for def, i in opts.defines {
        defs[i] = {
            Name = clone_to_cstring(def[0], context.temp_allocator),
            Definition = clone_to_cstring(def[1], context.temp_allocator),
        }
    }

    binary: ^d3d11.IBlob
    errors: ^d3d11.IBlob

    include_handler := D3D_Include_Handler{
        incl = {
            vtable = &d3d_compiler.ID3DInclude_VTable{
                Open = _d3dcompiler_include_open,
                Close = _d3dcompiler_include_close,
            },
        },
        opts = opts,
        ctx = context,
    }

    res := d3d_compiler.Compile(
        pSrcData = raw_data(source),
        SrcDataSize = len(source),
        pSourceName = clone_to_cstring(name, context.temp_allocator),
        pDefines = defs,
        pInclude = &include_handler,
        pEntrypoint = entry_point_name,
        pTarget = target_name,
        Flags1 = transmute(u32)flags,
        Flags2 = 0,
        ppCode = &binary,
        ppErrorMsgs = &errors,
    )

    if res != 0 {
        if errors != nil {
            str := string((cast([^]u8)errors->GetBufferPointer())[:errors->GetBufferSize()])
            base.log_err("Shader compile error:\n\t%s", str)
        }
        return {}, false
    }

    // TODO: FIXME: the binary gets leaked...
    result = (transmute([^]byte)binary->GetBufferPointer())[:binary->GetBufferSize()]

    return result, true
}

D3D_Include_Handler :: struct #all_or_none {
    #subtype incl:  d3d_compiler.ID3DInclude,
    ctx:            runtime.Context,
    opts:           Options,
}

_d3dcompiler_include_open ::  proc "system" (
    _this: ^d3d_compiler.ID3DInclude,
    IncludeType: d3d_compiler.INCLUDE_TYPE,
    pFileName: d3d_compiler.LPCSTR,
    pParentData: rawptr,
    ppData: ^rawptr,
    pBytes: ^u32,
) -> d3d_compiler.HRESULT {
    this := cast(^D3D_Include_Handler)_this

    context = this.ctx

    if this.opts.include_proc == nil {
        return transmute(d3d_compiler.HRESULT)u32(windows.E_FAIL)
    }

    result, ok := this.opts.include_proc(
        path = string(pFileName),
        user = this.opts.user,
    )

    if !ok {
        return transmute(d3d_compiler.HRESULT)u32(windows.E_FAIL)
    }

    ppData^ = raw_data(result)
    pBytes^ = u32(len(result))

    return windows.S_OK
}

_d3dcompiler_include_close :: proc "system" (
    this: ^d3d_compiler.ID3DInclude,
    pData: rawptr,
) -> d3d_compiler.HRESULT {
    // ignore
    return windows.S_OK
}

