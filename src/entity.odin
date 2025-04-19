package main

import "core:math/linalg"

entity_func :: #type proc(entity: ^Entity, state: ^State)
entity_draw_func :: #type proc(entity: ^Entity, shader: Shader, state: ^State)

Entity :: struct {
    userptr: rawptr,
    think: entity_func,
    should_think: bool,
    draw: entity_draw_func,
    should_draw: bool,
    destroy: entity_func,

    position: linalg.Vector3f32,
    angles: quaternion128,
}

Scene :: struct {
    entities: []^Entity,
    entity_count: i32,
    lights: []^Entity,
    light_count: i32,
}

scene_create :: proc(max_entities: i32, max_lights: i32) -> ^Scene {
    s := new(Scene)
    s.entities = make([]^Entity, max_entities)
    s.lights = make([]^Entity, max_lights)
    return s
}

scene_add_entity :: proc(scene: ^Scene, entity: ^Entity) -> ^Entity {
    scene.entities[scene.entity_count] = entity
    scene.entity_count += 1
    return entity
}

scene_add_light :: proc(scene: ^Scene, entity: ^Entity) -> ^Entity {
    scene.lights[scene.light_count] = entity
    scene.light_count += 1
    return entity
}

scene_update :: proc(state: ^State, scene: ^Scene) {
    for i in 0..<scene.entity_count {
        e := scene.entities[i]
        if e.should_think {
            e->think(state)
        }
    }
}

scene_render :: proc(state: ^State, scene: ^Scene, shader: Shader) {
    for i in 0..<scene.entity_count {
        e := scene.entities[i]
        if e.should_draw {
            e->draw(shader, state)
        }
    }
}

MAX_ENTITIES :: 2048

MAX_LIGHTS :: 16

g_lights := make([]^Entity, MAX_LIGHTS)
light_count := 0

g_entities := make([]^Entity, MAX_ENTITIES)
entity_count := 0

add_entity :: proc(entity: ^Entity) -> ^Entity {
    g_entities[entity_count] = entity
    entity_count += 1
    return entity
}

add_light :: proc(entity: ^Entity) -> ^Entity {
    g_lights[light_count] = entity
    light_count += 1
    return entity
}

debug_lights :: proc(state: ^State, shader: Shader) {
    for i in 0..<light_count {
        ent := g_lights[i]
        if ent.should_draw {
            ent->draw(shader, state)
        }
    }
}

update_entities :: proc(state: ^State) {
    for i in 0..<entity_count {
        ent := g_entities[i]
        if ent.should_think {
            ent->think(state)
        }
    }
}

render_entities :: proc(state: ^State, shader: Shader) {
    for i in 0..<entity_count {
        ent := g_entities[i]
        if ent.should_draw {
            ent->draw(shader, state)
        }
    }
}