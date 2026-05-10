package ravn_build

import "../platform"
import "../base"
import "../base/ufmt"

import "core:strconv"
import "core:strings"

WASM_PAGE_SIZE :: 65536

DEFAULT_INITIAL_MEM_PAGES :: 2000
DEFAULT_MAX_MEM_PAGES :: 65536

export_web :: proc(dst_dir: string, pkg_name: string, pkg_path: string) -> bool {
    remove_all(strings.concatenate({dst_dir, platform.SEPARATOR, "*"}))
    platform.create_directory(dst_dir)

    initial_mem_pages := DEFAULT_INITIAL_MEM_PAGES
    max_mem_pages := DEFAULT_MAX_MEM_PAGES

    base.log_info("Compiling WASM ...")

    if !compile_web(dst_dir,
        pkg_name = pkg_name,
        pkg_path = pkg_path,
        initial_mem_pages = initial_mem_pages,
        max_mem_pages = max_mem_pages,
    ) {
        base.log_info("Error: failed to compile to WASM")
        return false
    }

    base.log_info("Generating HTML and JS files ...")

    html := generate_html(
        title = pkg_name,
        pkg_name = pkg_name,
        initial_mem_pages = initial_mem_pages,
        max_mem_pages = max_mem_pages,
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/index.html", dst_dir),
        transmute([]byte)html,
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/odin.js", dst_dir),
        #load(ODIN_ROOT + "core/sys/wasm/js/odin.js"),
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/wgpu.js", dst_dir),
        #load(ODIN_ROOT + "vendor/wgpu/wgpu.js"),
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/ravn_platform.js", dst_dir),
        #load("../platform/ravn_platform.js"),
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/ravn_webaudio.js", dst_dir),
        #load("../audio/ravn_webaudio.js"),
    )

    platform.write_file_by_path(
        ufmt.tprintf("%s/ravn_webaudio_processor.js", dst_dir),
        #load("../audio/ravn_webaudio_processor.js"),
    )

    return true
}

compile_web :: proc(dst_dir: string, pkg_name: string, pkg_path: string, initial_mem_pages: int, max_mem_pages: int) -> bool {
    // NOTE: size optimizations are probably not worth the time when compiling debug builds.
    OPT_FLAGS :: "-debug "
    // OPT_FLAGS :: "-o:size -no-bounds-check -disable-assert -define:GPU_RELEASE=true "

    FORMAT :: "%s build %s -target:js_wasm32 -out:%s/%s.wasm " +
        "-define:RELEASE=true " +
        OPT_FLAGS +
        "-extra-linker-flags:\"--export-table --import-memory --initial-memory=%i --max-memory=%i\""

    return exec(ufmt.tprintf(FORMAT, ODIN_EXE, pkg_path, dst_dir, pkg_name,
        initial_mem_pages * WASM_PAGE_SIZE,
        max_mem_pages * WASM_PAGE_SIZE,
    ))
}

generate_html :: proc(
    title:              string,
    pkg_name:           string,
    initial_mem_pages:  int,
    max_mem_pages:      int,
) -> string {
    html := HTML_TEMPLATE

    // hacky

    buf: [256]u8

    html, _ = strings.replace_all(html, "@pkg", pkg_name)
    html, _ = strings.replace_all(html, "@title", title)
    html, _ = strings.replace_all(html, "@initial_mem_pages", strconv.write_int(buf[:], i64(initial_mem_pages), 10))
    html, _ = strings.replace_all(html, "@max_mem_pages", strconv.write_int(buf[:], i64(max_mem_pages), 10))

    return html
}

HTML_TEMPLATE :: `
<!DOCTYPE html>
<html lang="en" style="height: 100%;">
	<head>
		<meta charset="UTF-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>@title</title>
	</head>
	<body id="body" style="height: 100%; padding: 0; margin: 0; overflow: hidden;">
		<canvas id="ravn-canvas" style="height: 100%; width: 100%;"></canvas>

		<script type="text/javascript" src="odin.js"></script>
		<script type="text/javascript" src="wgpu.js"></script>
		<script type="text/javascript" src="ravn_platform.js"></script>
		<script type="text/javascript" src="ravn_webaudio.js"></script>

		<script type="text/javascript">
			const mem = new WebAssembly.Memory({
                initial: @initial_mem_pages,
                maximum: @max_mem_pages,
                shared: false,
            });
			const memInterface = new odin.WasmMemoryInterface();
			memInterface.setMemory(mem);

			const wgpuInterface = new odin.WebGPUInterface(memInterface);
			const ravnPlatformInterface = new odin.RavnPlatformInterface(memInterface);
            const ravnAudioInterface = new odin.RavnAudioInterface(memInterface);

            const foreignImports = {
                wgpu: wgpuInterface.getInterface(),
                ravn_platform: ravnPlatformInterface.getInterface(),
                ravn_audio: ravnAudioInterface.getInterface(),
            }

			odin.runWasm("@pkg.wasm", null, foreignImports, memInterface, /*intSize=8*/);
		</script>
	</body>
</html>
`