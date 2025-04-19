package main

import gl "vendor:opengl"

GBUFFER_FRAGMENT :: #load("../gbuffer_fragment.glsl", string)
GBUFFER_VERTEX :: #load("../gbuffer_vertex.glsl", string)

Gbuffer :: struct {
    handle: u32,
    positionMask, normalDepth, colorMetal, roughnessAo, lightDepth, rbo: u32,
    shader_pass: Shader,
}

gbuffer_shader: Shader = 0
fullscreen_quad: ^Model = nil

create_gbuffer :: proc(width, height: i32, shader_pass: u32) -> ^Gbuffer {
    buf := new(Gbuffer)
    gl.GenFramebuffers(1, &buf.handle)
    gl.BindFramebuffer(gl.FRAMEBUFFER, buf.handle)

    gl.GenRenderbuffers(1, &buf.rbo)
    gl.BindRenderbuffer(gl.RENDERBUFFER, buf.rbo)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT, width, height)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, buf.rbo)

    gl.GenTextures(1, &buf.positionMask)
    gl.GenTextures(1, &buf.normalDepth)
    gl.GenTextures(1, &buf.colorMetal)
    gl.GenTextures(1, &buf.roughnessAo)
    gl.GenTextures(1, &buf.lightDepth)

    make_buf_texture :: proc(texture: u32, num: u32, width, height: i32, format: i32, data: u32) {
        gl.BindTexture(gl.TEXTURE_2D, texture)
        gl.TexImage2D(gl.TEXTURE_2D, 0, format, width, height, 0, gl.RGBA, data, nil)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
        gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + num, gl.TEXTURE_2D, texture, 0)
    }

    make_buf_texture(buf.positionMask, 0, width, height, gl.RGBA16F, gl.FLOAT)
    make_buf_texture(buf.normalDepth, 1, width, height, gl.RGBA16F, gl.FLOAT)
    make_buf_texture(buf.colorMetal, 2, width, height, gl.RGBA, gl.UNSIGNED_BYTE)
    make_buf_texture(buf.roughnessAo, 3, width, height, gl.RGBA, gl.UNSIGNED_BYTE)
    make_buf_texture(buf.lightDepth, 4, width, height, gl.RGBA16F, gl.FLOAT)

    attachments := []u32{ gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1, gl.COLOR_ATTACHMENT2, gl.COLOR_ATTACHMENT3, gl.COLOR_ATTACHMENT4 }
    gl.DrawBuffers(i32(len(attachments)), &attachments[0])

    if gbuffer_shader == 0 {
        gbuffer_shader = load_shader_from_memory(GBUFFER_VERTEX, GBUFFER_FRAGMENT)
    }
    buf.shader_pass = shader_pass

    return buf
}

bind_gbuffer :: proc(buf: ^Gbuffer) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, buf.handle)
}

draw_gbuffer :: proc(state: ^State, buf: ^Gbuffer, uniform_set_proc: proc(state: ^State, buf: ^Gbuffer), debug: bool = false) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    gl.UseProgram(buf.shader_pass)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, buf.positionMask)
    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, buf.normalDepth)
    gl.ActiveTexture(gl.TEXTURE2)
    gl.BindTexture(gl.TEXTURE_2D, buf.colorMetal)
    gl.ActiveTexture(gl.TEXTURE3)
    gl.BindTexture(gl.TEXTURE_2D, buf.roughnessAo)
    gl.ActiveTexture(gl.TEXTURE4)
    gl.BindTexture(gl.TEXTURE_2D, buf.lightDepth)

    uniform_loc := get_location(buf.shader_pass, "gbuffer_position")
    gl.Uniform1i(uniform_loc, 0)
    gl.BindTexture(gl.TEXTURE_2D, buf.positionMask)
    uniform_loc = get_location(buf.shader_pass, "gbuffer_normal_depth")
    gl.Uniform1i(uniform_loc, 1)
    gl.BindTexture(gl.TEXTURE_2D, buf.normalDepth)
    uniform_loc = get_location(buf.shader_pass, "gbuffer_diffuse_metallic")
    gl.Uniform1i(uniform_loc, 2)
    gl.BindTexture(gl.TEXTURE_2D, buf.colorMetal)
    uniform_loc = get_location(buf.shader_pass, "gbuffer_roughness_ao")
    gl.Uniform1i(uniform_loc, 3)
    gl.BindTexture(gl.TEXTURE_2D, buf.roughnessAo)
    uniform_loc = get_location(buf.shader_pass, "gbuffer_light_depth")
    gl.Uniform1i(uniform_loc, 4)
    gl.BindTexture(gl.TEXTURE_2D, buf.lightDepth)

    uniform_set_proc(state, buf)

    draw_fullscreen_quad()
}

load_fullscreen_quad :: proc() {
    if fullscreen_quad == nil {
        fullscreen_quad = load_model_from_memory(#load("../quad.fbx", []u8))
    }
}

draw_fullscreen_quad :: proc() {
    if fullscreen_quad == nil {
        load_fullscreen_quad()
    }
    gl.BindVertexArray(fullscreen_quad.meshes[0].vao)
    gl.DrawElements(gl.TRIANGLES, fullscreen_quad.meshes[0].index_count, gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(0)
}