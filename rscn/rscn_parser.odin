// Raven Scene parser
#+vet explicit-allocators shadowing unused
package rscn

import "../base"
import "core:strings"
import "core:strconv"

// TODO: object to index meshes by string to allow for multi file scenes
// TODO: file section instead of img section
// TODO: reference files by name

VERSION_MAJOR :: 0
VERSION_MINOR :: 1

Elem :: union {
    Comment,
    Image,
    Mesh,
    Spline,
    Object,
}

Comment :: distinct string

Section :: enum {
    None = 0,
    Images,
    Meshes,
    Splines,
    Object,
}

Header :: struct {
    version_major:      int,
    version_minor:      int,

    image_num:          int,
    mesh_num:           int,
    mesh_index_offs:    int,
    mesh_vert_offs:     int,
    mesh_index_num:     int,
    mesh_vert_num:      int,
    object_num:         int,
    spline_num:         int,
    spline_vert_offs:   int,
    spline_vert_num:    int,
}

Object_Index :: int
Vertex_Index :: int
Image_Index :: int
Spline_Index :: int

Image :: struct {
    path:   string,
}

Object :: struct {
    kind:           Object_Kind,
    mesh_index:     Vertex_Index,
    spline_index:   Spline_Index,
    name:           string, // valid as long as the file data is valid
    parent:         Object_Index,
    image_index:    Image_Index,

    pos:            [3]f32,
    mat:            matrix[3, 3]f32,
}

Object_Kind :: enum u8 {
    Empty = 0,
    Mesh,
    Spline,
}

Mesh :: struct {
    name:           string, // valid as long as the file data is valid
    index_num:      int,
    vert_num:       int,
    index_start:    int,
    vert_start:     int,
}

#assert(size_of(Mesh_Vertex) == 26)

Mesh_Vertex :: struct #packed {
    pos:    [3]f32,
    uv:     [2]f32,
    normal: [3]u8,
    color:  [3]u8,
}

Spline :: struct {
    name:       string,
    vert_num:   int,
    vert_start: int,
}

Spline_Vertex :: struct {
    pos:    [3]f32,
    rad:    f32,
    tilt:   f32,
}

Parser :: struct {
    iter:       string,
    section:    Section,
}

Error :: enum u8 {
    OK = 0,
    End,
    Error,
}

init_parser :: proc(p: ^Parser, data: string) {
    p.iter = data
    p.section = .None
}

make_parser :: proc(data: string) -> (result: Parser) {
    init_parser(&result, data)
    return result
}

parse_header :: proc(p: ^Parser) -> (result: Header, err: Error) {
    if len(p.iter) < 5 {
        base.log_err("rscn: file is too short to be valid")
        return {}, .Error
    }


    if
        p.iter[0] != 'r' ||
        p.iter[1] != 's' ||
        p.iter[2] != 'c' ||
        p.iter[3] != 'n'
    {
        base.log_err("rscn: header magic mismatch: '%s'", p.iter[:4])
        return {}, .Error
    }

    p.iter = p.iter[4:]

    if p.iter[0] == '\r' {
        p.iter = p.iter[1:]
    }

    if p.iter[0] == '\n' {
        p.iter = p.iter[1:]
    }

    result.version_major = -1

    line_loop: for {
        line, line_ok := strings.split_lines_iterator(&p.iter)
        if !line_ok {
            return {}, .End
        }

        if len(line) == 0 {
            break line_loop
        }

        if len(line) < 4 {
            base.log_err("rscn: invalid header entry")
            return {}, .Error
        }

        field := line[:4]
        line = line[4:]

        switch field {
        case "ver ":
            result.version_major = _parse_int(&line) or_return
            result.version_minor = _parse_int(&line) or_return

        case "msh ":
            result.mesh_num = _parse_int(&line) or_return
            result.mesh_index_offs = _parse_hex(&line) or_return
            result.mesh_index_num = _parse_hex(&line) or_return
            result.mesh_vert_offs = _parse_hex(&line) or_return
            result.mesh_vert_num = _parse_hex(&line) or_return

        case "spl ":
            result.spline_num = _parse_int(&line) or_return
            result.spline_vert_offs = _parse_hex(&line) or_return
            result.spline_vert_num = _parse_hex(&line) or_return

        case "img ": result.image_num = _parse_int(&line) or_return
        case "obj ": result.object_num = _parse_int(&line) or_return

        case:
            base.log_err("rscn: Unknown header field '%v'", line[:3])
            return {}, .Error
        }
    }

    if result.version_major != VERSION_MAJOR || result.version_minor != VERSION_MINOR {
        base.log_err("rscn: version mismatch")
        return {}, .Error
    }

    return result, .OK
}

parse_next_elem :: proc(p: ^Parser) -> (result: Elem, err: Error) {
    line_loop: for {
        line, line_ok := strings.split_lines_iterator(&p.iter)
        if !line_ok {
            return {}, .End
        }

        // base.log_info("line %v", line)

        if len(line) == 0 {
            continue
        }

        switch line[0] {
        case '@':
            switch line[1:] {
            case "imgs": p.section = .Images
            case "mshs": p.section = .Meshes
            case "spls": p.section = .Splines
            case "objs": p.section = .Object

            case:
                // Invalid
                return {}, .Error
            }

            continue line_loop

        case '#':
            text := strings.trim_space(line[1:])
            return Comment(text), .OK
        }

        switch p.section {
        case .None:
            assert(false, "You must first call 'parse_header'")
            return {}, .Error

        case .Images:
            return Image{path = line}, .OK

        case .Meshes:
            mesh: Mesh

            mesh.name = _parse_ident(&line) or_return

            mesh.index_num = _parse_int(&line) or_return
            mesh.vert_num = _parse_int(&line) or_return

            mesh.index_start = _parse_hex(&line) or_return
            mesh.vert_start = _parse_hex(&line) or_return

            return mesh, .OK

        case .Splines:
            spline: Spline

            spline.name = _parse_ident(&line) or_return
            spline.vert_num = _parse_int(&line) or_return
            spline.vert_start = _parse_hex(&line) or_return

            return spline, .OK

        case .Object:
            object: Object

            if len(line) < 5 {
                return {}, .Error
            }

            kind := line[:4]
            line = line[4:]

            switch kind {
            case "emp ":
                object.kind = .Empty

            case "spl ":
                object.kind = .Spline

            case "msh ":
                object.kind = .Mesh
                object.mesh_index = _parse_int(&line) or_return
            }

            object.name = _parse_ident(&line) or_return

            object.parent = _parse_int(&line) or_return
            object.image_index = _parse_int(&line) or_return

            _expect_prefix(&line, " [")
            object.pos = {
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
            }
            _expect_char(&line, ']')

            _expect_prefix(&line, " [")
            object.mat[0] = {
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
            }
            object.mat[1] = {
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
            }
            object.mat[2] = {
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
                _parse_float(&line) or_return,
            }
            _expect_char(&line, ']')

            return object, .OK
        }
    }
}

_expect_char :: proc(line: ^string, ch: u8) -> Error {
    if line[0] == ch {
        line^ = line[1:]
        return .OK
    }
    _strict_error()
    return .Error
}

_expect_prefix :: proc(line: ^string, str: string) -> Error {
    if strings.starts_with(line^, str) {
        line^ = line[len(str):]
        return .OK
    }
    _strict_error()
    return .Error
}

_skip_whitespace :: proc(line: ^string) {
    for i in 0..<len(line^) {
        switch line[i] {
        case ' ':
        case '\t':
        case:
            line^ = line[i:]
            return
        }
    }
}

_parse_ident :: proc(line: ^string) -> (string, Error) {
    _skip_whitespace(line)
    for i in 0..<len(line^) {
        ch := line[i]
        switch ch {
        case '_', '.', ':':
        case 'a'..='z':
        case 'A'..='Z':
        case '0'..='9':
        case ' ':
            ident := line[:i]
            line^ = line[i:]
            return ident, .OK
        case:
            base.log_err("Found invalid identifier character")
            _strict_error()
            return "", .Error
        }
    }
    _strict_error()
    return "", .Error
}


_parse_float :: proc(line: ^string) -> (f32, Error) {
    _skip_whitespace(line)
    num := 0
    val, _ := strconv.parse_f32(line^, &num)
    if num == 0 {
        _strict_error()
        return 0, .Error
    }
    line^ = line[num:]
    return val, .OK
}

_parse_int :: proc(line: ^string) -> (int, Error) {
    _skip_whitespace(line)
    num := 0
    val, _ := strconv.parse_int(line^, 10, &num)
    if num == 0 {
        _strict_error()
        return 0, .Error
    }
    line^ = line[num:]
    return val, .OK
}

_parse_hex :: proc(line: ^string) -> (int, Error) {
    _skip_whitespace(line)
    num := 0
    val, _ := strconv.parse_int(line^, 16, &num)
    if num == 0 {
        _strict_error()
        return 0, .Error
    }
    line^ = line[num:]
    return val, .OK
}

_strict_error :: proc() {
    assert(false)
}