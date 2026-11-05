shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Disruptive camouflage on soldier uniforms: two octaves of value noise in
// UV space cut into four colour blotches, with a fine fabric weave on top.

uniform vec3 c_base : source_color = vec3(0.33, 0.36, 0.24);
uniform vec3 c_a : source_color = vec3(0.24, 0.27, 0.17);
uniform vec3 c_b : source_color = vec3(0.38, 0.31, 0.21);
uniform vec3 c_c : source_color = vec3(0.12, 0.12, 0.10);
uniform float scale = 9.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV * scale;
	float n1 = vnoise(uv) * 0.65 + vnoise(uv * 2.3 + 7.1) * 0.35;
	float n2 = vnoise(uv * 1.4 + 19.7) * 0.6 + vnoise(uv * 3.1 + 3.3) * 0.4;
	vec3 col = c_base;
	col = mix(col, c_a, step(0.56, n1));
	col = mix(col, c_b, step(0.62, n2));
	col = mix(col, c_c, step(0.72, n1) * step(0.45, n2));
	float weave = (sin(UV.x * 900.0) * sin(UV.y * 900.0)) * 0.03;
	ALBEDO = col * (0.97 + weave);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
