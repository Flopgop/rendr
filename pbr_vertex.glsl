#version 330 core
layout (location = 0) in vec3 position;
layout (location = 1) in vec3 normal;
layout (location = 2) in vec2 texcoords;
layout (location = 3) in vec3 tangent;
layout (location = 4) in vec3 bitangent;

out vec2 frag_texcoord;
out vec3 frag_worldpos;
out vec3 frag_normal;

out mat3 TBN;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main()
{
    mat3 normalMatrix = transpose(inverse(mat3(model)));
    frag_texcoord = texcoords;
    frag_worldpos = vec3(model * vec4(position, 1.0));
    frag_normal = normalMatrix * normal;

    vec3 N = normalize(normal);
    vec3 T = normalize(tangent);
    vec3 B = normalize(bitangent);
    TBN = mat3(T, B, N);

    gl_Position = projection * view * model * vec4(position, 1.0);
}