shader_type sky;
// The island's sky: the same gradient and sun as before, plus two layers of
// soft drifting cumulus. Clouds are flat layers projected onto the dome, so
// they thin out toward the horizon like real ones, and the sun lights their
// edges. `cover` sets how much of the sky they fill (weather), `cloud_tint`
// their colour, and the radiance pass (lighting) gets them at reduced detail.

uniform vec3 sky_top_color : source_color = vec3(0.16, 0.34, 0.66);
uniform vec3 sky_horizon_color : source_color = vec3(0.62, 0.76, 0.90);
uniform vec3 ground_horizon_color : source_color = vec3(0.60, 0.73, 0.87);
uniform vec3 ground_bottom_color : source_color = vec3(0.36, 0.52, 0.64);
uniform float sky_curve = 0.13;
uniform float ground_curve = 0.08;
uniform float energy = 1.05;
uniform float cover = 0.45;
uniform vec3 cloud_tint : source_color = vec3(1.0);
uniform float cloud_dark = 0.55;
uniform float wind = 1.0;
// Cloud drift in seconds, advanced from the script every few seconds (the
// built-in clock here would redo the sky's lighting every frame).
uniform float drift = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col;
	// Same gradient as Godot's procedural sky.
	if (y >= 0.0) {
		float c = 1.0 - acos(clamp(y, -1.0, 1.0)) / (PI * 0.5);
		col = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else {
		float c = 1.0 - acos(clamp(-y, -1.0, 1.0)) / (PI * 0.5);
		col = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	}
	// Sun disc and its glow.
	vec3 sd = LIGHT0_DIRECTION;
	float sa = dot(d, sd);
	vec3 sun_c = LIGHT0_COLOR * LIGHT0_ENERGY;
	if (LIGHT0_ENABLED) {
		col += sun_c * pow(max(sa, 0.0), 220.0) * 0.6;
		col += sun_c * pow(max(sa, 0.0), 8.0) * 0.08;
		if (sa > 0.99965) {
			col = mix(col, sun_c * 4.0, smoothstep(0.99965, 0.9999, sa));
		}
	}
	// Clouds: a layer at "height" 1 seen along the ray.
	if (y > 0.015 && cover > 0.01) {
		float t = drift * 0.004 * wind;
		vec2 uv = d.xz / (y + 0.06) * 0.9;
		int oct = AT_CUBEMAP_PASS ? 3 : 5;
		float base = fbm(uv * 1.2 + vec2(t, t * 0.6), oct);
		float detail = fbm(uv * 4.5 - vec2(t * 2.0, 0.0), AT_CUBEMAP_PASS ? 1 : 3);
		float dens = base * 0.78 + detail * 0.28;
		float thr = 1.0 - cover * 0.9;
		float c = smoothstep(thr - 0.02, thr + 0.22, dens);
		// Thin out toward the horizon, where you look through haze.
		c *= smoothstep(0.015, 0.22, y);
		// Shading: darker, flatter undersides where the cloud is thick, a
		// bright rim toward the sun.
		float thick = smoothstep(thr, thr + 0.45, dens);
		vec3 lit = mix(cloud_tint, cloud_tint * cloud_dark, thick * 0.8);
		lit += sun_c * pow(max(sa, 0.0), 6.0) * 0.35 * (1.0 - thick);
		lit = mix(lit, col, (1.0 - smoothstep(0.0, 0.35, y)) * 0.45);
		col = mix(col, lit, c * 0.92);
	}
	COLOR = col * energy;
}
