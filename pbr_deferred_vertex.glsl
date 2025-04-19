#version 330 core
layout (location = 0) in vec3 position;
layout (location = 1) in vec3 normal;
layout (location = 2) in vec2 texcoords;
layout (location = 3) in vec3 tangent;
layout (location = 4) in vec3 bitangent;

out vec2 frag_texcoord;

void main()
{
    frag_texcoord = vec2(texcoords.x, -texcoords.y);
    gl_Position = vec4(position, 1.0);
}