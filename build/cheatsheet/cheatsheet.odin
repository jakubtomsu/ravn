// Markdown cheatsheet generator
package ravn_build_cheatsheet

import "core:log"
import doc "core:odin/doc-format"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import "../../base"

OUT_PATH :: "CHEATSHEET.md"

Proc_Entry :: struct {
    sig:    string,
    doc:    string,
    file:   string,
    offset: u32,
}

Package_Entry :: struct {
    name:   string,
    path:   string, // full path with forward slashes
    procs:  [dynamic]Proc_Entry,
}

main :: proc() {
    context.logger = base.make_logger()

    state, stdout, stderr, err := os.process_exec({
        command = {
            "odin",
            "doc",

            "base",
            "gpu",
            "platform",
            "geometry",
            "imgui",
            "debugdraw",
            "bvh",
            "collision",
            "shader_compiler",
            "scene",
            "input",

            "-all-packages",
            "-doc-format",
            "-in-source-order",
            "-out:./cheatsheet.odin-doc",

        }
    }, allocator = context.allocator)

    if err != nil {
        log.error("Failed to launch Odin executable:", err)
        os.exit(1)
    }

    if !state.success {
        log.errorf("odin doc failed with exit code %d", state.exit_code)
        if len(stderr) > 0 do fmt.eprintf("%s\n", stderr)
        if len(stdout) > 0 do fmt.printf("%s\n", stdout)
        os.exit(1)
    }

    log.info("Odin doc generated successfully")

    doc_path := "./cheatsheet.odin-doc"

    data, data_err := os.read_entire_file_from_path(doc_path, context.allocator)
    if data_err != nil {
        log.errorf("failed to read '%s': %v", doc_path, data_err)
        os.exit(1)
    }

    header, header_err := doc.read_from_bytes(data)
    if header_err != nil {
        log.errorf("failed to parse '%s': %v", doc_path, header_err)
        os.exit(1)
    }

    root: string
    if wd, wd_err := os.get_working_directory(context.allocator); wd_err == nil {
        root = normalize_slashes(wd)
    } else {
        log.errorf("failed to get working directory: %v", wd_err)
        os.exit(1)
    }

    pkgs := make(map[string]^Package_Entry)
    parse_packages_from_doc(header, root, &pkgs)

    md := generate_cheatsheet_markdown(pkgs)

    if err := os.write_entire_file(OUT_PATH, transmute([]byte)md); err != nil {
        log.errorf("failed to write '%s': %v", OUT_PATH, err)
        os.exit(1)
    }

    log.infof("wrote %s (%d packages)", OUT_PATH, len(pkgs))
}

parse_packages_from_doc :: proc(header: ^doc.Header, root: string, dst_pkgs: ^map[string]^Package_Entry) {
    files := doc.from_array(&header.base, header.files)
    entities := doc.from_array(&header.base, header.entities)

    for pkg in doc.from_array(&header.base, header.pkgs)[1:] {
        full := normalize_slashes(get_str(header, pkg.fullpath))
        if !strings.has_prefix(full, root) {
            continue
        }

        pe := new(Package_Entry)
        pe.name = get_str(header, pkg.name)
        pe.path = full

        if strings.has_prefix(pe.name, "ravn_") {
            pe.name = pe.name[len("ravn_"):]
        }

        for entry in doc.from_array(&header.base, pkg.entries) {
            ent := entities[entry.entity]

            #partial switch ent.kind {
            case .Procedure, .Proc_Group:
            case:
                continue
            }

            name := get_str(header, ent.name)

            if strings.has_prefix(name, "_") do continue

            if .Private in ent.flags || .Foreign in ent.flags {
                continue
            }

            file_name: string
            if int(ent.pos.file) < len(files) {
                file_name = filepath.base(normalize_slashes(get_str(header, files[ent.pos.file].name)))
            }

            append(&pe.procs, Proc_Entry{
                sig    = clean_signature(name, get_str(header, ent.init_string)),
                doc    = doc_line(get_str(header, ent.comment), get_str(header, ent.docs)),
                file   = file_name,
                offset = u32(ent.pos.offset),
            })
        }

        dst_pkgs[full] = pe
    }

    return

    get_str :: proc(header: ^doc.Header, str: doc.String) -> string {
        return doc.from_string(&header.base, str)
    }
}

generate_cheatsheet_markdown :: proc(pkgs: map[string]^Package_Entry) -> string {
    ordered := make([dynamic]^Package_Entry, 0, len(pkgs))
    for _, pe in pkgs {
        append(&ordered, pe)
    }
    slice.sort_by(ordered[:], proc(a, b: ^Package_Entry) -> bool {
        return a.path < b.path
    })

    b := strings.builder_make()

    fmt.sbprintfln(&b, "# RAVN Cheatsheet")
    fmt.sbprintln(&b, "> Generated with `build/cheatsheet`")
    fmt.sbprintln(&b, "")

    // Table of contents.
    fmt.sbprintln(&b, "## Packages")
    fmt.sbprintln(&b, "")
    for pe in ordered {
        if len(pe.procs) == 0 do continue
        fmt.sbprintfln(&b, "- [%s](#%s) - %d procedures", pe.name, pe.name, len(pe.procs))
    }
    fmt.sbprintln(&b, "")

    for pe in ordered {
        if len(pe.procs) == 0 do continue

        fmt.sbprintfln(&b, "## %s", pe.name)
        fmt.sbprintln(&b, "")

        procs := pe.procs[:]
        slice.sort_by(procs, proc(a, b: Proc_Entry) -> bool {
            if a.file != b.file do return a.file < b.file
            return a.offset < b.offset
        })

        i := 0
        for i < len(procs) {
            file := procs[i].file
            j := i
            for j < len(procs) && procs[j].file == file {
                j += 1
            }

            group := procs[i:j]

            if file != "" {
                fmt.sbprintfln(&b, "### %s", file)
                fmt.sbprintln(&b, "")
            }
            fmt.sbprintln(&b, "```odin")

            for p in group {
                if p.doc == "" {
                    fmt.sbprintfln(&b, "%s", p.sig)
                } else {
                    fmt.sbprintfln(&b, "%s // %s", p.sig, p.doc)
                }
            }

            fmt.sbprintln(&b, "```")
            fmt.sbprintln(&b, "")

            i = j
        }
    }

    return strings.to_string(b)
}

clean_signature :: proc(name: string, init: string) -> string {
    sig := init

    if idx := strings.index(sig, " /* "); idx >= 0 {
        sig = sig[:idx]
    }
    sig = strings.trim_right_space(sig)

    if strings.has_prefix(sig, "proc{") {
        return fmt.tprintf("%s :: %s", name, sig)
    }

    sig = strings.trim_suffix(sig, "{...}")
    sig = strings.trim_right_space(sig)
    sig = strings.trim_suffix(sig, "---")
    sig = strings.trim_right_space(sig)

    rest := strings.trim_prefix(sig, "proc")
    return fmt.tprintf("%s%s", name, rest)
}

doc_line :: proc(comment: string, docs: string) -> string {
    if c := strings.trim_space(comment); c != "" {
        return collapse(c)
    }
    if d := strings.trim_space(docs); d != "" {
        return collapse(first_line(d))
    }
    return ""
}

first_line :: proc(str: string) -> string {
    s := strings.trim_space(str)
    if idx := strings.index_byte(s, '\n'); idx >= 0 {
        return strings.trim_space(s[:idx])
    }
    return s
}

collapse :: proc(s: string) -> string {
    b := strings.builder_make()
    prev_space := false
    for r in s {
        if r == '\r' || r == '\n' || r == '\t' || r == ' ' {
            if !prev_space {
                strings.write_byte(&b, ' ')
                prev_space = true
            }
        } else {
            strings.write_rune(&b, r)
            prev_space = false
        }
    }
    return strings.trim_space(strings.to_string(b))
}

normalize_slashes :: proc(s: string) -> string {
    out, _ := strings.replace_all(s, "\\", "/")
    return out
}
