#+private=file
package ravn_build

import "../platform"
import "../base"
import "../base/ufmt"

import "core:strings"
import "core:strconv"
import "base:runtime"

when ODIN_OS == .Windows {
    DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
    DLL_EXT :: ".dylib"
} else {
    DLL_EXT :: ".so"
}

Hotreload_Module :: struct {
    mod:        platform.Module,
    desc:       base.App_Desc,
    callback:   proc "contextless" (rawptr, base.App_Desc) -> rawptr,
}

Hotreload_File :: struct {
    path:       string,
    index:      int,
}

exec :: proc(str: string) -> bool {
    res := platform.run_shell_command(str)
    if 0 != res {
        base.log_err("Error: Command '%s' failed with exit code %i", str, res)
        return false
    }
    return true
}

compile_hot :: proc(pkg: string, pkg_name: string, index: int) {
    path := ufmt.tprintf("%s%i" + DLL_EXT, pkg_name, index)
    assert(!platform.file_exists(path), ufmt.tprintf("!platform.file_exists(\"%s\")", path))
    exec(ufmt.tprintf("%s build %s -out:%s -debug -build-mode:dll", ODIN_EXE, pkg, path))
}

clean_hot :: proc(pkg: string) {
    when ODIN_OS == .Windows {
        remove_all(ufmt.tprintf("%s*.dll", pkg))
        remove_all(ufmt.tprintf("%s*.pdb", pkg))
        remove_all(ufmt.tprintf("%s*.exp", pkg))
        remove_all(ufmt.tprintf("%s*.lib", pkg))
        remove_all(ufmt.tprintf("%s*.rdi", pkg))
    } else when ODIN_OS == .Linux {
        remove_all(ufmt.tprintf("./%s*.so", pkg)) // linux dll
    }
}

/// Taken from  Odin/core/os/path_linux.odin
when ODIN_OS == .Linux || ODIN_OS == .Darwin{
    _is_path_separator :: proc(c: byte) -> bool {
        _Path_Separator        :: '/'
        return c == _Path_Separator
    }

    @(require_results)
    split_path :: proc(path: string) -> (dir, filename: string) {
        i := len(path) - 1
        for i >= 0 && !_is_path_separator(path[i]) {
            i -= 1
        }
        if i == 0 {
            return path[:i+1], path[i+1:]
        } else if i > 0 {
            return path[:i], path[i+1:]
        }
        return "", path
    }


    /// Taken from  Odin/core/os/path.odin
    /*
    Gets the file name and extension from a path.

    e.g.
        'path/to/name.tar.gz' -> 'name.tar.gz'
        'path/to/name.txt'    -> 'name.txt'
        'path/to/name'        -> 'name'

    Returns "." if the path is an empty string.
    */
    filepath_base :: proc(path: string) -> string {
        if path == "" {
            return "."
        }

        _, file := split_path(path)
        return file
    }
}

hotreload_find_latest_dll :: proc(pkg_name: string) -> (result: Hotreload_File, ok: bool) {
    when ODIN_OS == .Windows {
        pattern := ufmt.tprintf("%s*" + DLL_EXT, pkg_name)
        PATH_SEPARATOR :: "\\"
    } else when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        pattern := ufmt.tprintf("./%s*" + DLL_EXT, pkg_name)
        PATH_SEPARATOR :: "/"
    }
    max_index: int = -1

    iter: platform.Directory_Iter
    for path in platform.iter_directory(&iter, pattern, context.temp_allocator) {
        path_parts := strings.split(path, PATH_SEPARATOR)
        base_filename := path_parts[len(path_parts)-1]
        if !strings.starts_with(base_filename, pkg_name) {
            continue
        }

        if !strings.has_suffix(base_filename, DLL_EXT) {
            continue
        }

        index_str := base_filename[len(pkg_name) : len(base_filename) - len(DLL_EXT)]

        digits: int
        index, _ := strconv.parse_int(index_str, 10, &digits)

        if digits == 0 {
            continue
        }

        if index > max_index {
            max_index = index
            result = {
                path    = path,
                index   = index,
            }
            ok = true
        }
    }

    return result, ok
}

hotreload_run :: proc(pkg: string, pkg_path: string) -> bool {
    initial, initial_ok := hotreload_find_latest_dll(pkg)

    if !initial_ok {
        base.log_err("Hotreload Error: Couldn't find inital DLL for package:", pkg)
        return false
    }

    base.log_info("Hotreload: Loading initial module %s ...", initial.path)

    module, module_ok := load_hotreload_module(initial.path)

    if !module_ok {
        base.log_err("Hotreload Error: Failed to load initial DLL")
        return false
    }

    modules_to_unload: [dynamic]platform.Module
    append(&modules_to_unload, module.mod)

    curr_index := initial.index

    prev_data: rawptr

    watcher: platform.File_Watcher
    platform.init_file_watcher(&watcher, pkg_path)

    any_changes := false

    for {
        assert(module.callback != nil)

        prev_data = module.callback(prev_data, module.desc)

        if prev_data == nil {
            break
        }

        prev_any_changes := any_changes

        changes := platform.poll_file_watcher(&watcher)
        for change in changes {
            // base.log_info("Hotreload: file changed:", change)
            if strings.ends_with(change, ".odin") {
                any_changes = true
            }
        }

        if prev_any_changes && any_changes {
            any_changes = false

            // EXPERIMENTAL
            // Sometimes fails with:
            // Syntax Error: Failed to parse file: something.odin; invalid file or cannot be found
            // base.log_info("HOTRELOADAUTO RECOMPILING")
            // compile_hot(pkg_path, pkg, curr_index + 1)
        }

        new_file, new_ok := hotreload_find_latest_dll(pkg)
        if !new_ok {
            continue
        }

        if new_file.index > curr_index {
            // NOTE: this is expected to fail a few times while the module is compiling.
            new_module, new_module_ok := load_hotreload_module(new_file.path)
            if !new_module_ok {
                platform.sleep_ms(50)
                continue
            }

            base.log_info("Hotreload: Loaded %s", new_file.path)

            if new_module.desc.state_size != module.desc.state_size {
                base.log_err(
                    "Hotreload: State size mismatch (new %i vs old %i). You cannot change the State struct layout during hotreload.",
                    new_module.desc.state_size, module.desc.state_size)
                return false
            }

            append(&modules_to_unload, new_module.mod)

            module = new_module
            curr_index = new_file.index
        }

        free_all(context.temp_allocator)
    }

    for lib, i in modules_to_unload {
        platform.unload_module(lib)
    }

    base.log_info("Hotreload: finished OK")

    return true
}

load_hotreload_module :: proc(path: string) -> (result: Hotreload_Module, ok: bool) {
    module, module_ok := platform.load_module(path)
    if !module_ok {
        base.log_err("Hotreload: Failed to load library:", path)
        return {}, false
    }

    app_desc_ptr := cast(^base.App_Desc)platform.get_module_symbol_address(module, "_app_desc")

    if app_desc_ptr == nil {
        base.log_err("Hotreload: Failed to find _app_desc data")
        return {}, false
    }

    result.desc = app_desc_ptr^

    result.callback = auto_cast(platform.get_module_symbol_address(module, "_module_hot_step"))

    if result.callback == nil {
        base.log_err("Hotreload: Failed to find the _module_hot_step proc")
        return {}, false
    }

    return result, true
}
