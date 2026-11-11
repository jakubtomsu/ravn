package ravn_shaderc

when ODIN_OS != .Windows {
    _DXBC_Blob :: struct {}
    _dxbc_blob_destroy :: proc(blob: ^_DXBC_Blob) {}
}