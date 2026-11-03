shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural "part" material for the voxel gun meshes.
// The meshes have no UVs, so colours are derived from model-space position:
// barrel = blued steel, receiver = dark gunmetal, stock/grip = walnut.

uniform vec3 gunmetal : source_color = vec3(0.085, 0.092, 0.104);
uniform vec3 steel : source_color = vec3(0.255, 0.270, 0.295);
uniform vec3 wood : source_color = vec3(0.335, 0.175, 0.082);
uniform vec3 accent : source_color = vec3(0.72, 0.36, 0.10);
uniform float wear = 0.35;
uniform float accent_amount = 0.0;

varying vec3 v_pos;
varying vec3 v_nrm;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x),
			   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 p = v_pos;
	float z = p.z;
	float y = p.y;
	float ax = abs(p.x);

	vec3 base = gunmetal;

	// Long forward tube -> blued steel.
	float barrel = smoothstep(-0.16, -0.34, z);
	base = mix(base, steel * 0.85, barrel);

	// Rear stock -> walnut furniture.
	float stock = smoothstep(0.20, 0.34, z);
	base = mix(base, wood, stock);

	// Top rail / carry handle.
	float rail = smoothstep(0.075, 0.115, y) * smoothstep(-0.30, -0.16, z);
	base = mix(base, steel * 1.02, rail * 0.85);

	// Foregrip / magazine / pistol grip.
	float grip = smoothstep(-0.02, -0.075, y) * smoothstep(-0.28, -0.10, z) * smoothstep(0.34, 0.16, z);
	base = mix(base, wood * 0.92, grip * 0.8);

	// Narrow upper receiver block.
	float recv = smoothstep(0.02, 0.05, y) * smoothstep(-0.30, -0.10, z) * smoothstep(0.30, 0.12, z);
	base = mix(base, steel * 0.7, recv * 0.30);

	// Muzzle / front sight accent.
	float muzzle = smoothstep(-0.40, -0.47, z);
	base = mix(base, accent, muzzle * accent_amount);
	base = mix(base, steel * 1.25, muzzle * (1.0 - accent_amount) * 0.55);

	// Micro grime + edge wear.
	float grain = vnoise(p * 62.0) * 0.5 + vnoise(p * 190.0) * 0.25;
	base *= 1.0 - wear * 0.22 * grain;
	float edge = pow(1.0 - clamp(abs(dot(normalize(v_nrm), normalize(vec3(0.35, 1.0, 0.2)))), 0.0, 1.0), 2.0);
	base += vec3(0.05) * edge * wear * grain;

	ALBEDO = base;
	ROUGHNESS = mix(0.72, 0.28, clamp(rail + recv + barrel * 0.7, 0.0, 1.0));
	METALLIC = mix(0.12, 0.85, clamp(rail + barrel + recv, 0.0, 1.0));
	SPECULAR = 0.55;
	AO = mix(0.65, 1.0, clamp(1.0 - ax * 1.2, 0.0, 1.0));
}
