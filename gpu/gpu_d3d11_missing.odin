#+build windows
package ravn_gpu

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

// Temporary

when BACKEND == BACKEND_D3D11 {

    ID3DDeviceContextState_UUID_STRING :: "5c1e0d8a-7c23-48f9-8c59-a92958ceff11"
    ID3DDeviceContextState_UUID := &dxgi.IID{0x5c1e0d8a, 0x7c23, 0x48f9, {0x8c, 0x59, 0xa9, 0x29, 0x58, 0xce, 0xff, 0x11}}

    ID3DDeviceContextState :: struct #raw_union {
        #subtype id3d11devicechild: d3d11.IDeviceChild,
        using id3d11devicechild_vtable: ^d3d11.IDeviceChild_VTable,
    }

    ID3D11DeviceContext1_UUID_STRING :: "bb2c6faa-b5fb-4082-8e6b-388b8cfa90e1"
    ID3D11DeviceContext1_UUID := &dxgi.IID{0xbb2c6faa, 0xb5fb, 0x4082, {0x8e, 0x6b, 0x38, 0x8b, 0x8c, 0xfa, 0x90, 0xe1}}
    ID3D11DeviceContext1 :: struct #raw_union {
        #subtype id3d11devicecontext: d3d11.IDeviceContext,
        using id3d11devicecontext1_vtable: ^ID3D11DeviceContext1_VTable,
    }
    ID3D11DeviceContext1_VTable :: struct {
        using id3d11devicecontext_vtable: d3d11.IDeviceContext_VTable,

        CopySubresourceRegion1: proc "system" (
            this: ^ID3D11DeviceContext1,
            pDstResource: ^d3d11.IResource,
            DstSubresource: u32,
            DstX: u32,
            DstY: u32,
            DstZ: u32,
            pSrcResource: ^d3d11.IResource,
            SrcSubresource: u32,
            pSrcBox: ^d3d11.BOX, // opt // const
            CopyFlags: u32,
        ),

        UpdateSubresource1: proc "system" (
            this: ^ID3D11DeviceContext1,
            pDstResource: ^d3d11.IResource,
            DstSubresource: u32,
            pDstBox: ^d3d11.BOX, // opt // const
            pSrcData: rawptr, // const
            SrcRowPitch: u32,
            SrcDepthPitch: u32,
            CopyFlags: u32,
        ),

        DiscardResource: proc "system" (
            this: ^ID3D11DeviceContext1,
            pResource: ^d3d11.IResource,
        ),

        DiscardView: proc "system" (
            this: ^ID3D11DeviceContext1,
            pResourceView: ^d3d11.IView,
        ),

        VSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        HSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        DSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        GSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        PSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        CSSetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // reads NumBuffers
            pFirstConstant: ^u32, // reads NumBuffers
            pNumConstants: ^u32, // reads NumBuffers
        ),

        VSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        HSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        DSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        GSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        PSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        CSGetConstantBuffers1: proc "system" (
            this: ^ID3D11DeviceContext1,
            StartSlot: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT
            NumBuffers: u32, // in range 0..<D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT - StartSlot
            ppConstantBuffers: [^]^d3d11.IBuffer, // writes NumBuffers
            pFirstConstant: ^u32, // writes NumBuffers
            pNumConstants: ^u32, // writes NumBuffers
        ),

        SwapDeviceContextState: proc "system" (
            this: ^ID3D11DeviceContext1,
            pState: ^ID3DDeviceContextState,
            ppPreviousState: ^^ID3DDeviceContextState, // optional out
        ),

        ClearView: proc "system" (
            this: ^ID3D11DeviceContext1,
            pView: ^d3d11.IView,
            Color: ^[4]f32,
            pRect: ^d3d11.RECT, // reads NumRects
            NumRects: u32,
        ),

        DiscardView1: proc "system" (
            this: ^ID3D11DeviceContext1,
            pResourceView: ^d3d11.IView,
            pRects: ^d3d11.RECT, // reads NumRects
            NumRects: u32,
        ),

    }

}