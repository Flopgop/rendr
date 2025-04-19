package main

import "vendor:glfw"
import math "core:math"
import gl "vendor:opengl"
import "core:math/linalg"
import back "incl/back"
import time "core:time"
import "core:fmt"
import "core:strings"

import im "incl/imgui"
import "incl/imgui/imgui_impl_glfw"
import "incl/imgui/imgui_impl_opengl3"

Camera :: struct {
    position: linalg.Vector3f32,
    target: linalg.Vector3f32,
    up: linalg.Vector3f32,
    fov: f32,
    near: f32,
    far: f32,

    dirty: bool,

    view: linalg.Matrix4f32,
    projection: linalg.Matrix4f32,
}

State :: struct {
    window: glfw.WindowHandle,
    model_registry: map[Identifier]^Model,

    gbuffer: ^Gbuffer,
    current_scene: ^Scene,

    frame_delta, game_time: f32,
    camera: Camera,
}

light_shader: Shader

update_camera :: proc(camera: ^Camera, width, height: f32) {
    if camera.dirty {
        camera.dirty = false
        camera.view = linalg.matrix4_look_at_f32(camera.position, camera.target, camera.up)
        camera.projection = linalg.matrix4_perspective_f32(camera.fov, width/height, camera.near, camera.far)
    }
}

load_models :: proc(state: ^State) {
    state.model_registry["default:backpack"] = load_model_from_file("backpack.obj")
    state.model_registry["default:plane"] = load_model_from_file("plane.obj")
}

main :: proc () {
    back.register_segfault_handler()
    if !glfw.Init() do panic("glfw")

    state := new(State)
    state.window = glfw.CreateWindow(1280, 720, "window", nil, nil)

    glfw.SetWindowUserPointer(state.window, state)

    glfw.MakeContextCurrent(state.window)

    gl.load_up_to(4, 6, glfw.gl_set_proc_address)

    glfw.SetWindowSizeCallback(state.window, proc "c" (window: glfw.WindowHandle, width, height: i32) {
        gl.Viewport(0,0,width,height)
    })

    im.CHECKVERSION()
    im.CreateContext()
    defer im.DestroyContext()
    io := im.GetIO()
    io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
    io.ConfigFlags += {.DockingEnable}
    io.ConfigFlags += {.ViewportsEnable}

    style := im.GetStyle()
    style.WindowRounding = 0
    style.Colors[im.Col.WindowBg].w = 1

    im.StyleColorsDark()

    imgui_impl_glfw.InitForOpenGL(state.window, true)
    defer imgui_impl_glfw.Shutdown()
    imgui_impl_opengl3.Init("#version 150")
    defer imgui_impl_opengl3.Shutdown()

    load_fallback_texture()
    load_light_debug_model()
    load_fullscreen_quad()
    load_models(state)

    light_shader = load_shader_from_memory(#load("../light_vertex.glsl", string), #load("../light_fragment.glsl", string))

    state.current_scene = scene_create(16, 3)

    state.camera = {
        {2,2,2},
        {0,0,0},
        {0,1,0},
        math.to_radians_f32(90),
        0.01,
        1000.0,
        true,
        linalg.MATRIX4F32_IDENTITY,
        linalg.MATRIX4F32_IDENTITY
    }

    pbr_shader := load_shader_from_memory(#load("../pbr_deferred_vertex.glsl", string), #load("../pbr_deferred_fragment.glsl", string))

    state.gbuffer = create_gbuffer(1280, 720, pbr_shader)

    movy_model := new_movy_model(state.model_registry["default:backpack"])

    ((^MovyModel)(movy_model.userptr)).delta_rot = {0,0.2,0}
    ((^MovyModel)(movy_model.userptr)).scale = {0.25, 0.25, 0.25}

    scene_add_entity(state.current_scene, movy_model)

    plane := new_movy_model(state.model_registry["default:plane"])
    scene_add_entity(state.current_scene, plane)

    light := scene_add_light(state.current_scene, new_light({
        {3,1,1},
        100,
        false
    }))
    light.position = {-2,2,2}

    state.frame_delta = 0

    for !glfw.WindowShouldClose(state.window) {
        start := time.tick_now()

        update(state)

        render(state)

        dur := time.tick_since(start)
        state.frame_delta = f32(time.duration_seconds(dur))
    }
}

update :: proc(state: ^State) {
    state.game_time += state.frame_delta

    glfw.PollEvents()
    width, height := glfw.GetWindowSize(state.window)

    update_camera(&state.camera, f32(width), f32(height))

    scene_update(state, state.current_scene)
}

render :: proc(state: ^State) {
    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 2, -1, "Frame")

    gl.ClearColor(0.69, 0.69, 0.69, 0)
    bind_gbuffer(state.gbuffer)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    render_world(state)

    draw_to_screen(state)

    render_ui(state)

    glfw.SwapBuffers(state.window)
    gl.PopDebugGroup()
}

render_world :: proc(state: ^State) {
    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 1, -1, "World")
    gl.Enable(gl.DEPTH_TEST)
    gl.Disable(gl.BLEND)
    gl.DepthMask(true)
    gl.DepthFunc(gl.LEQUAL)
    defer {
        gl.Disable(gl.DEPTH_TEST)
        gl.Disable(gl.CULL_FACE)
        gl.Enable(gl.BLEND)
    }

    width, height := glfw.GetFramebufferSize(state.window)

    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 1, -1, "Shadows")
    gl.UseProgram(light_shader)
    rotation := linalg.matrix3_from_quaternion(g_lights[0].angles)
    light_space_matrix := linalg.matrix4_perspective_f32(math.to_degrees_f32(40), f32(width) / f32(height), 0.1, 10.0) * linalg.matrix4_look_at(g_lights[0].position, rotation * linalg.Vector3f32{0,0,-1}, linalg.Vector3f32{0,1,0})
    gl.UniformMatrix4fv(get_location(light_shader, "light_space_matrix"), 1, false, &light_space_matrix[0][0])
    scene_render(state, state.current_scene, light_shader)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    gl.PopDebugGroup()

    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 1, -1, "Gbuffer")
    scene_render(state, state.current_scene, gbuffer_shader)
    gl.PopDebugGroup()
    gl.PopDebugGroup()
}

render_ui :: proc(state: ^State) {
    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 0, -1, "UI")

    imgui_impl_opengl3.NewFrame()
    imgui_impl_glfw.NewFrame()
    im.NewFrame()

    im.ShowDemoWindow()

    im.Render()
    imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
    backup_current_window := glfw.GetCurrentContext()
    im.UpdatePlatformWindows()
    im.RenderPlatformWindowsDefault()
    glfw.MakeContextCurrent(backup_current_window)

    gl.PopDebugGroup()
}

draw_to_screen :: proc(state: ^State) {
    gl.PushDebugGroup(gl.DEBUG_SOURCE_APPLICATION, 3, -1, "Gbuffer Blit + Lighting")
    draw_gbuffer(state, state.gbuffer, proc(state: ^State, buf: ^Gbuffer) {
        num_lights_location := get_location(buf.shader_pass, "num_lights")
        cam_pos_location := get_location(buf.shader_pass, "cam_pos")

        gl.Uniform3f(cam_pos_location, state.camera.position.x, state.camera.position.y, state.camera.position.z)
        gl.Uniform1i(num_lights_location, i32(light_count))

        for i in 0..<light_count {
            light := g_lights[i]
            light_position_loc := get_location(buf.shader_pass, strings.unsafe_string_to_cstring(fmt.tprintf("lights[%v].position", i)))
            light_color_loc := get_location(buf.shader_pass, strings.unsafe_string_to_cstring(fmt.tprintf("lights[%v].color", i)))

            gl.Uniform3f(light_position_loc, light.position.x, light.position.y, light.position.z)
            gl.Uniform3f(light_color_loc, ((^Light)(light.userptr)).color.x * ((^Light)(light.userptr)).intensity, ((^Light)(light.userptr)).color.y * ((^Light)(light.userptr)).intensity, ((^Light)(light.userptr)).color.z * ((^Light)(light.userptr)).intensity)
        }
    })
    gl.PopDebugGroup()
}