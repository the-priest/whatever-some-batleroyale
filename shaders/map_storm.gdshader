shader_type canvas_item;

// The storm on the map: everything outside the current circle sits under a
// drifting purple haze with a bright edge, and the next safe zone is a clean
// white ring. Drawn over the terrain and under the markers.

uniform vec2 view_origin = vec2(-1200.0, -1200.0);
uniform vec2 view_span = vec2(2400.0, 2400.0);
uniform float px_per_m = 0.25;
uniform vec2 zone_c = vec2(0.0);
uniform float zone_r = 1250.0;
uniform vec2 next_c = vec2(0.0);
uniform float next_r = 600.0;
uniform float show_zone = 1.0;
uniform float show_next = 1.0;
uniform vec3 storm_col : source_color = vec3(0.47, 0.27, 0.92);
uniform vec3 edge_col : source_color = vec3(0.86, 0.74, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 w = view_origin + UV * view_span;
	vec3 col = vec3(0.0);
	float a = 0.0;

	if (show_zone > 0.5) {
		float px = (length(w - zone_c) - zone_r) * px_per_m;
		float outside = smoothstep(-0.8, 0.8, px);
		// Cloud that drifts round the eye, in screen-sized swirls so it reads
		// the same on the minimap and on the full map.
		vec2 q = w * px_per_m / 46.0;
		float n = fbm(q + vec2(TIME * 0.045, -TIME * 0.03));
		n = fbm(q * 0.7 + n * 1.6 + vec2(-TIME * 0.02, TIME * 0.035));
		vec3 haze = storm_col * (0.62 + 0.75 * n);
		float fill = outside * (0.40 + 0.22 * n);
		// Glow that falls off into the storm, and a crisp line on the wall.
		float glow = exp(-max(px, 0.0) / 16.0) * outside;
		float line = 1.0 - smoothstep(0.6, 1.9, abs(px));
		haze = mix(haze, edge_col, clamp(glow * 0.55, 0.0, 1.0));
		col = mix(haze, edge_col, line);
		a = max(fill + glow * 0.22, line * 0.96);
	}

	if (show_next > 0.5) {
		float dn = abs(length(w - next_c) - next_r) * px_per_m;
		float halo = (1.0 - smoothstep(1.0, 4.5, dn)) * 0.42;
		float ring = 1.0 - smoothstep(0.55, 1.6, dn);
		// Dark halo under the ring, then the ring itself.
		col = mix(col, vec3(0.02, 0.03, 0.05), halo / max(a + halo - a * halo, 0.0001));
		a = a + halo - a * halo;
		col = mix(col, vec3(1.0), ring);
		a = max(a, ring);
	}

	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
