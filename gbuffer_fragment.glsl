#version 330 core
layout (location = 0) out vec4 gbuffer_position_mask;
layout (location = 1) out vec4 gbuffer_normal_depth;
layout (location = 2) out vec4 gbuffer_diffuse_metallic;
layout (location = 3) out vec4 gbuffer_roughness_ao;

in vec2 frag_texcoord;
in vec3 frag_worldpos;
in vec3 frag_normal;
in mat4 M;
in mat3 TBN;

uniform sampler2D texture_diffuse1;
uniform sampler2D texture_metallic1;
uniform sampler2D texture_roughness1;
uniform sampler2D texture_normal1;
uniform sampler2D texture_ao1;

vec3 getNormalFromMap()
{
    vec3 tangentNormal = texture(texture_normal1, frag_texcoord).xyz * 2.0 - 1.0;

    tangentNormal.xy *= 3.0;
    tangentNormal = normalize(tangentNormal);

    return normalize(TBN * tangentNormal);
}

void main() {
    gbuffer_position_mask.rgb = frag_worldpos;
    gbuffer_position_mask.a = 1.0;
    gbuffer_normal_depth.rgb = normalize(vec3(M * vec4(getNormalFromMap(), 1.0)));
    gbuffer_normal_depth.a = gl_FragCoord.z;
    gl_FragDepth = gl_FragCoord.z;
    gbuffer_diffuse_metallic.rgb = texture(texture_diffuse1, frag_texcoord).rgb;
    gbuffer_diffuse_metallic.a = texture(texture_metallic1, frag_texcoord).r;
    gbuffer_roughness_ao.r = texture(texture_roughness1, frag_texcoord).r;
    gbuffer_roughness_ao.g = texture(texture_ao1, frag_texcoord).r;
}



