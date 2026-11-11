shader_type spatial;
render_mode cull_disabled;
// A kit surface (roof tiles, plaster) recoloured house by house. The
// MultiMesh instance colour carries the new hue (rgb) and how far to take it
// (a): a = 0 keeps the original, a = 1 swaps the colour while keeping each
// texel's light and dark. `ref_lum` is the texture's typical brightness.
// Triplanar mode maps it in world space (the gable infills have no UVs).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = true;
uniform bool use_rough_tex = true;
uniform float rough = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float ref_lum = 0.32;
uniform bool triplanar = false;
uniform float tri_scale = 0.5;

varying vec4 inst;
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	inst = COLOR;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	if (triplanar) {
		vec3 an = abs(w_nrm);
		uv = (an.x > an.y && an.x > an.z) ? w_pos.zy : ((an.y > an.z) ? w_pos.xz : w_pos.xy);
		uv *= tri_scale;
		uv.y = -uv.y;
	}
	vec3 t = texture(albedo_tex, uv).rgb;
	float l = dot(t, vec3(0.299, 0.587, 0.114));
	vec3 recol = inst.rgb * (l / ref_lum);
	ALBEDO = mix(t, recol, clamp(inst.a, 0.0, 1.0)) * tint;
	ROUGHNESS = (use_rough_tex ? texture(rough_tex, uv).r : 1.0) * rough;
	if (use_normal && !triplanar) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
}
