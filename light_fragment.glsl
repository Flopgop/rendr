#version 330 core

layout (location = 4) out vec3 gbuffer_light_depth;

void main() {
    gbuffer_light_depth = vec3(gl_FragCoord.z);
}