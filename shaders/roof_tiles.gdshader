shader_type spatial;
render_mode cull_disabled;
// The kit's round roof tiles, recoloured house by house. The MultiMesh
// instance colour carries the new hue (rgb) and how far to take it (a):
// a = 0 keeps the fired-clay terracotta, a = 1 is slate, moss or brown with
// the same shading and wear as the original tiles.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rough = 1.0;
uniform vec3 tint : source_color = vec3(1.0);

varying vec4 inst;

void vertex() {
	inst = COLOR;
}

void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	float l = dot(t, vec3(0.299, 0.587, 0.114));
	// Keep the light and dark of each tile, swap its colour.
	vec3 recol = inst.rgb * (l / 0.32);
	ALBEDO = mix(t, recol, clamp(inst.a, 0.0, 1.0)) * tint;
	ROUGHNESS = texture(rough_tex, UV).r * rough;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
