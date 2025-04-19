#version 330 core

#define LIGHT_COUNT 16

out vec4 FragColor;

in vec2 frag_texcoord;
in vec3 frag_worldpos;
in vec3 frag_normal;
in mat3 TBN;

struct Light {
    vec3 position;
    vec3 color;
};

uniform vec3 cam_pos;
const float PI = 3.14159265359;

uniform Light lights[LIGHT_COUNT];
uniform int num_lights;
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

vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float DistributionGGX(vec3 N, vec3 H, float roughness)
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

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

void main()
{
    vec3 N = normalize(frag_normal);
    vec3 V = normalize(cam_pos - frag_worldpos);

    vec3 albedo = pow(texture(texture_diffuse1, frag_texcoord).rgb, vec3(2.2));
    float metallic = texture(texture_metallic1, frag_texcoord).r;
    float roughness = texture(texture_roughness1, frag_texcoord).r;
    float ao = texture(texture_ao1, frag_texcoord).r;

    vec3 Lo = vec3(0.0);
    for (int i = 0; i < num_lights; ++i) {
        vec3 L = normalize(lights[i].position - frag_worldpos);
        vec3 H = normalize(V + L);

        float dist = length(lights[i].position - frag_worldpos);
        float attenuation = 1.0 / (dist * dist);
        vec3 radiance = lights[i].color * attenuation;

        vec3 F0 = vec3(0.04);
        F0 = mix(F0, albedo, metallic);
        vec3 F = fresnelSchlick(max(dot(H,V), 0.0), F0);

        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);

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