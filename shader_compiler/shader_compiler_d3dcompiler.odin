package ravn_shader_compiler

when ODIN_OS != .Windows {
    _DXBC_Blob :: struct {}
    _dxbc_blob_destroy :: proc(blob: ^_DXBC_Blob) {}
}