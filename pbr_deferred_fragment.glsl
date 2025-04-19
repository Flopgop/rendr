#version 330 core

#define LIGHT_COUNT 16

in vec2 frag_texcoord;

out vec4 FragColor;

struct Light {
    vec3 position;
    vec3 color;
};

uniform sampler2D gbuffer_position_mask;
uniform sampler2D gbuffer_normal_depth;
uniform sampler2D gbuffer_diffuse_metallic;
uniform sampler2D gbuffer_roughness_ao;

uniform vec3 cam_pos;
const float PI = 3.14159265359;

uniform Light lights[LIGHT_COUNT];
uniform int num_lights;

vec3 fresnel_schlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float distribution_ggx(vec3 N, vec3 H, float roughness)
{
    float a      = roughness*roughness;
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float num   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float geometry_schlick_ggx(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}
float geometry_smith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = geometry_schlick_ggx(NdotV, roughness);
    float ggx1  = geometry_schlick_ggx(NdotL, roughness);

    return ggx1 * ggx2;
}

void main()
{
    vec4 pos_mask = texture(gbuffer_position_mask, frag_texcoord);
    if (pos_mask.a <= 0) discard;
    vec3 worldpos = pos_mask.rgb;

    vec4 normal_depth = texture(gbuffer_normal_depth, frag_texcoord);
    if (normal_depth.a >= 1.0) discard;

    vec4 diffuse_metallic = texture(gbuffer_diffuse_metallic, frag_texcoord);
    vec4 roughness_ao = texture(gbuffer_roughness_ao, frag_texcoord);

    vec3 N = normal_depth.rgb;
    vec3 V = normalize(cam_pos - worldpos);

    vec3 albedo = pow(diffuse_metallic.rgb, vec3(2.2));
    float metallic = diffuse_metallic.a;
    float roughness = roughness_ao.r;
    float ao = roughness_ao.g;

    vec3 Lo = vec3(0.0);
    for (int i = 0; i < num_lights; ++i) {
        vec3 L = normalize(lights[i].position - worldpos);
        vec3 H = normalize(V + L);

        float dist = length(lights[i].position - worldpos);
        float attenuation = 1.0 / (dist * dist);
        vec3 radiance = lights[i].color * attenuation;

        vec3 F0 = vec3(0.04);
        F0 = mix(F0, albedo, metallic);
        vec3 F = fresnel_schlick(max(dot(H,V), 0.0), F0);

        float NDF = distribution_ggx(N, H, roughness);
        float G = geometry_smith(N, V, L, roughness);

        vec3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        vec3 specular = numerator / denominator;

        vec3 kS = F;
        vec3 kD = vec3(1.0) - kS;

        kD *= 1.0 - metallic;

        float NdotL = max(dot(N, L), 0.0);

        Lo += (kD * albedo / PI + specular) * radiance * NdotL;
    }

    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo;

    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));

    FragColor = vec4(color, 1.0);
}