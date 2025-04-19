package main

import "core:math/linalg"

LIGHT_MODEL: ^Model

Light :: struct {
    color: [3]f32,
    intensity: f32,

    shadow_mapped: bool,
}

load_light_debug_model :: proc() {
    LIGHT_MODEL = load_model_from_memory(#load("../ball.fbx"))
}

new_light :: proc(data: Light) -> ^Entity {
    entity := new(Entity)
    light := new(Light)

    light.color = data.color
    light.intensity = data.intensity
    light.shadow_mapped = false

    entity.should_draw = false
    entity.draw = light_draw
    entity.should_think = false
    entity.position = {0,0,0}
    entity.angles = linalg.QUATERNIONF32_IDENTITY
    entity.userptr = light

    entity.destroy = proc(entity: ^Entity, state: ^State) {}

    return entity
}

light_draw :: proc(light: ^Entity, shader: Shader, state: ^State) {
    model_draw(LIGHT_MODEL, shader)
}
