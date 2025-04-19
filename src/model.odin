package main

import ai "incl/assimp"
import gl "vendor:opengl"
import stbi "vendor:stb/image"

import "core:strings"

import "core:math/linalg"
import fmt "core:fmt"

Vertex :: struct {
    position, normal: linalg.Vector3f32,
    texcoords: linalg.Vector2f32,
    tangent, bitangent: linalg.Vector3f32,
    bone_ids: []i32,
    weights: []f32,
}

Texture :: struct {
    id: u32,
    type: string,
    path: string,
}

Mesh :: struct {
    textures: []Texture,

    vao, vbo, ebo: u32,
    index_count: i32,
}

Model :: struct {
    directory: string,

    textures_loaded: [dynamic]Texture,
    meshes: [dynamic]^Mesh,
}

Identifier :: string

FALLBACK_TEXTURE: u32

load_fallback_texture :: proc() {
    gl.GenTextures(1, &FALLBACK_TEXTURE)
    gl.BindTexture(gl.TEXTURE_2D, FALLBACK_TEXTURE)

    black := []u8{0,0,0,255}
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &black[0])

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
}

DEFAULT_FLAGS :: u32(ai.aiPostProcessSteps.Triangulate) | u32(ai.aiPostProcessSteps.FlipUVs) | u32(ai.aiPostProcessSteps.CalcTangentSpace) | u32(ai.aiPostProcessSteps.GenNormals) | u32(ai.aiPostProcessSteps.OptimizeMeshes) | u32(ai.aiPostProcessSteps.FlipWindingOrder)

load_model_from_file :: proc(path: cstring, flags: u32 = DEFAULT_FLAGS) -> ^Model {
    scene := ai.import_file(path, flags)
    return load_model_from_scene(scene, string(path))
}

load_model_from_memory :: proc(data: []u8, flags: u32 = DEFAULT_FLAGS, file_extension: cstring = "", texture_path: string = "") -> ^Model {
    scene := ai.import_file_from_memory(&data[0], u32(len(data)), flags, file_extension)
    return load_model_from_scene(scene, texture_path)
}

load_model_from_scene :: proc(scene: ^ai.aiScene, texture_path: string) -> ^Model {
    model := new(Model)
    path_s := texture_path
    last_index := strings.last_index(path_s, "/")
    if last_index < 0 do model.directory = ""
    else do model.directory, _ = strings.substring(path_s, 0, last_index)

    if scene != nil && scene.mRootNode != nil {
        process_node(model, scene.mRootNode, scene)
    } else {
        if scene == nil {
            fmt.panicf("Scene was nil! %s", ai.get_error_string())
        } else if scene.mRootNode == nil {
            fmt.panicf("Scene did not have a root node! %s", ai.get_error_string())
        }
        fmt.panicf("Unreachable")
    }
    return model
}

process_node :: proc(model: ^Model, node: ^ai.aiNode, scene: ^ai.aiScene) {
    for i in 0..<node.mNumMeshes {
        mesh := scene.mMeshes[node.mMeshes[i]]
        process_mesh(model, mesh, scene)
    }
    for i in 0..<node.mNumChildren {
        process_node(model, node.mChildren[i], scene)
    }
}

process_mesh :: proc(model: ^Model, mesh: ^ai.aiMesh, scene: ^ai.aiScene) {
    fmt.printfln("Making mesh %s", transmute(string)(mesh.mName.data[:mesh.mName.length]))
    vertices := make([]Vertex, mesh.mNumVertices)
    indices: [dynamic]u32
    textures: [dynamic]Texture

    for i in 0..<mesh.mNumVertices {
        vertices[i].position = mesh.mVertices[i]
        vertices[i].normal = mesh.mNormals[i]
        if mesh.mTextureCoords[0] != nil {
            vertices[i].texcoords = mesh.mTextureCoords[0][i].xy
            vertices[i].tangent = mesh.mTangents[i]
            vertices[i].bitangent = mesh.mBitangents[i]
        }
    }

    for i in 0..<mesh.mNumFaces {
        face := mesh.mFaces[i]
        for j in 0..<face.mNumIndices {
            append(&indices, face.mIndices[j])
        }
    }

    if mesh.mMaterialIndex >= 0 {
        material := scene.mMaterials[mesh.mMaterialIndex]
        diffuses := load_material_textures(model, material, ai.aiTextureType.DIFFUSE, "texture_diffuse")
        append(&textures, ..diffuses)
        other_color_textures := load_material_textures(model, material, ai.aiTextureType.BASE_COLOR, "texture_diffuse")
        append(&textures, ..other_color_textures)
        normals := load_material_textures(model, material, ai.aiTextureType.HEIGHT, "texture_normal")
        append(&textures, ..normals)
        metallic := load_material_textures(model, material, ai.aiTextureType.METALNESS, "texture_metallic")
        append(&textures, ..metallic)
        ambient := load_material_textures(model, material, ai.aiTextureType.AMBIENT, "texture_ao")
        append(&textures, ..ambient)
        roughness := load_material_textures(model, material, ai.aiTextureType.SHININESS, "texture_roughness")
        append(&textures, ..roughness)

        for i in ai.aiTextureType.NONE..<ai.aiTextureType.UNKNOWN {
            count := ai.get_material_textureCount(material, i)
            if count > 0 &&
                i != ai.aiTextureType.DIFFUSE &&
                i != ai.aiTextureType.HEIGHT &&
                i != ai.aiTextureType.METALNESS &&
                i != ai.aiTextureType.AMBIENT &&
                i != ai.aiTextureType.SHININESS &&
                i != ai.aiTextureType.BASE_COLOR
            {
                fmt.printfln("Model expects %v texture(s) of type %s but we don't know how to use them!", count, i)
            }
        }
    }

    append(&model.meshes, mesh_new(vertices, indices[:], textures[:]))

    delete(vertices)
    delete(indices)
}

load_material_textures :: proc(model: ^Model, mat: ^ai.aiMaterial, type: ai.aiTextureType, type_name: string) -> []Texture {
    texture_count := ai.get_material_textureCount(mat, type)
    textures := make([]Texture, texture_count)
    for i in 0..<texture_count {
        str: ai.aiString
        ai.get_material_texture(mat, type, i, &str, nil, nil, nil, nil, nil)
        tex_name := transmute(string)(str.data[:str.length])
        skip := false
        for j in 0..<len(model.textures_loaded) {
            if model.textures_loaded[j].path == tex_name {
                textures[i] = model.textures_loaded[j]
                skip = true
                break
            }
        }
        if !skip {
            texture: Texture
            texture.id = load_texture_from_file(tex_name, model.directory)
            texture.type = type_name
            texture.path = tex_name
            textures[i] = texture
            append(&model.textures_loaded, texture)
            fmt.printfln("Loaded texture %s with type %s", tex_name, type_name)
        }
    }
    return textures
}

load_texture_from_file :: proc(file, dir: string) -> u32 {
    dir := dir
    if dir == "" do dir = "."
    fullpath := fmt.aprintf("%s/%s", dir, file)
    defer delete(fullpath)

    id: u32
    gl.GenTextures(1, &id)
    width, height, nr_components: i32
    stbi.set_flip_vertically_on_load(1)
    data := stbi.load(strings.unsafe_string_to_cstring(fullpath), &width, &height, &nr_components, 0)
    defer stbi.image_free(data)
    if data != nil {
        format: i32
        if nr_components == 1 do format = gl.RED
        else if nr_components == 3 do format = gl.RGB
        else if nr_components == 4 do format = gl.RGBA

        gl.BindTexture(gl.TEXTURE_2D, id)
        gl.TexImage2D(gl.TEXTURE_2D, 0, format, width, height, 0, u32(format), gl.UNSIGNED_BYTE, data)
        gl.GenerateMipmap(gl.TEXTURE_2D)

        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    } else {
        fmt.panicf("failed to load texture %s", fullpath)
    }
    return id
}

mesh_new :: proc(vertices: []Vertex, indices: []u32, textures: []Texture) -> ^Mesh {
    mesh := new(Mesh)
    gl.GenVertexArrays(1, &mesh.vao)
    gl.GenBuffers(1, &mesh.vbo)
    gl.GenBuffers(1, &mesh.ebo)

    gl.BindVertexArray(mesh.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), &vertices[0], gl.STATIC_DRAW)

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, normal))

    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, texcoords))

    gl.EnableVertexAttribArray(3)
    gl.VertexAttribPointer(3, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, tangent))

    gl.EnableVertexAttribArray(4)
    gl.VertexAttribPointer(4, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, bitangent))

    gl.EnableVertexAttribArray(5)
    gl.VertexAttribIPointer(5, 4, gl.INT, size_of(Vertex), offset_of(Vertex, bone_ids))

    gl.EnableVertexAttribArray(6)
    gl.VertexAttribPointer(6, 4, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, weights))

    gl.BindVertexArray(0)

    mesh.textures = textures
    mesh.index_count = i32(len(indices))

    return mesh
}

mesh_draw :: proc(mesh: ^Mesh, shader: Shader) {
    gl.UseProgram(shader)
    diffuseNr := 1
    specularNr := 1
    normalNr := 1
    heightNr := 1
    for i in 0..<len(mesh.textures) {
        gl.ActiveTexture(gl.TEXTURE0 + u32(i))
        number: string
        defer delete(number)
        name := mesh.textures[i].type
        if name == "texture_diffuse" {
            number = fmt.aprintf("%v", diffuseNr)
            diffuseNr += 1
        } else if name == "texture_specular" {
            number = fmt.aprintf("%v", specularNr)
            specularNr += 1
        } else if name == "texture_normal" {
            number = fmt.aprintf("%v", normalNr)
            normalNr += 1
        } else if name == "texture_height" {
            number = fmt.aprintf("%v", heightNr)
            heightNr += 1
        }
        uniform_name := fmt.caprintf("%s%s", name, number)
        defer delete(uniform_name)
        uniform_loc := get_location(shader, uniform_name)
        gl.Uniform1i(uniform_loc, i32(i))
        gl.BindTexture(gl.TEXTURE_2D, mesh.textures[i].id)
    }
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindVertexArray(mesh.vao)
    gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(0)
}

mesh_destroy :: proc(mesh: ^Mesh) {
    gl.DeleteVertexArrays(1, &mesh.vao)
    gl.DeleteBuffers(1, &mesh.vbo)
    gl.DeleteBuffers(1, &mesh.ebo)
}

model_draw :: proc(model: ^Model, shader: Shader) {
    max_tex_units: i32
    gl.GetIntegerv(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS, &max_tex_units)
    for i in 0..<u32(max_tex_units) {
        gl.ActiveTexture(gl.TEXTURE0 + i)
        gl.BindTexture(gl.TEXTURE_2D, FALLBACK_TEXTURE)
    }
    for mesh in model.meshes {
        mesh_draw(mesh, shader)
    }
}

model_destroy :: proc(model: ^Model) {
    for mesh in model.meshes {
        mesh_destroy(mesh)
    }
}