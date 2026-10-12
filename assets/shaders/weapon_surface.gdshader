shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.15, 0.17, 0.18, 1.0);
uniform float metalness : hint_range(0.0, 1.0) = 0.85;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.38;
uniform bool walnut = false;
varying vec3 local_position;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
		mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
		mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() { local_position = VERTEX; }

void fragment() {
	vec3 p = local_position;
	float detail = noise(p * 210.0);
	if (walnut) {
		// Grain follows the stock's length, with broad colour variation and fine pores.
		float figure = noise(p * vec3(43.0, 38.0, 4.0));
		float phase = p.x * 1500.0 + p.y * 900.0 + figure * 24.0;
		float filtering = 1.0 - smoothstep(1.0, 5.0, fwidth(phase));
		float grain = sin(phase) * 0.075 * filtering;
		ALBEDO = base_color.rgb * (0.74 + figure * 0.48 + grain + detail * 0.045);
		ROUGHNESS = clamp(base_roughness + figure * 0.09 + grain * 0.3, 0.35, 0.78);
	} else {
		float patina = noise(p * 42.0);
		ALBEDO = base_color.rgb * (0.88 + patina * 0.18 + detail * 0.06);
		ROUGHNESS = clamp(base_roughness + (detail - 0.5) * 0.1, 0.24, 0.9);
	}
	METALLIC = metalness;
}
