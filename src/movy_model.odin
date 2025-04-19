package main

import "core:math/linalg"
import gl "vendor:opengl"

MovyModel :: struct {
    velocity: linalg.Vector3f32,
    delta_rot: linalg.Vector3f32,

    scale: linalg.Vector3f32,

    model: ^Model,
}

new_movy_model :: proc(model: ^Model) -> ^Entity {
    ent := new(Entity)
    data := new(MovyModel)

    data.velocity = {0,0,0}
    data.delta_rot = {0,0,0}
    data.scale = {1,1,1}
    data.model = model

    ent.userptr = data
    ent.think = movy_model_think
    ent.should_think = true
    ent.draw = movy_model_draw
    ent.should_draw = true
    ent.destroy = movy_model_destroy

    ent.position = {0,0,0}
    ent.angles = linalg.QUATERNIONF32_IDENTITY
    return ent
}

movy_model_think :: proc(entity: ^Entity, state: ^State) {
    movy_model_data := (^MovyModel)(entity.userptr)
    entity.position += movy_model_data.velocity * state.frame_delta
    delta_angle := movy_model_data.delta_rot * state.frame_delta
    entity.angles *= linalg.quaternion_from_euler_angles_f32(delta_angle.x, delta_angle.y, delta_angle.z, linalg.Euler_Angle_Order.XYZ)
    entity.angles = linalg.normalize(entity.angles)
}

movy_model_draw :: proc(entity: ^Entity, shader: Shader, state: ^State) {
    movy_model_data := (^MovyModel)(entity.userptr)
    gl.UseProgram(shader)
    model_loc := get_location(shader, "model")
    view_loc := get_location(shader, "view")
    projection_loc := get_location(shader, "projection")

    if model_loc >= 0 {
        model := linalg.matrix4_translate_f32(entity.position) * linalg.matrix4_from_quaternion_f32(entity.angles) * linalg.matrix4_scale_f32(movy_model_data.scale)
        gl.UniformMatrix4fv(model_loc, 1, false, &model[0][0])
    }
    if view_loc >= 0 {
        gl.UniformMatrix4fv(view_loc, 1, false, &state.camera.view[0][0])
    }
    if projection_loc >= 0 {
        gl.UniformMatrix4fv(projection_loc, 1, false, &state.camera.projection[0][0])
    }

    model_draw(movy_model_data.model, shader)
}

movy_model_destroy :: proc(entity: ^Entity, state: ^State) {
    movy_model_data := (^MovyModel)(entity.userptr)
    model_destroy(movy_model_data.model)
}