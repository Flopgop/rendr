package main

import gl "vendor:opengl"
import fmt "core:fmt"

Shader :: u32

load_shader_from_memory :: proc(vs, fs: string, loc := #caller_location) -> Shader {
    shader, ok := gl.load_shaders_source(vs, fs)
    assert(ok, fmt.aprintf("shader: %s", gl.get_last_error_message()), loc)
    return shader
}

get_location :: proc(shader: Shader, name: cstring) -> i32 {
    loc := gl.GetUniformLocation(shader, name)
    return loc
}

shader_set_int :: proc(shader: Shader, name: cstring, #any_int i: int) {
    loc := get_location(shader, name)
    gl.UseProgram(shader)
    gl.Uniform1i(loc, i32(i))
}