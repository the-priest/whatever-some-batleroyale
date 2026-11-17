shader_type spatial;

// Sawn timber. Every beam, post, plank, deck and shutter in the world is made
// of boards whose grain runs along its length, with a seam between boards, the
// odd butt joint with its two nails, and rings on the sawn ends.
//
// The wood itself comes from the two grain bands of the kit's trim sheet; this
// shader lays it out board by board instead of tiling the whole sheet (which
// also holds end grain and a stone strip) across everything.
//
// Where the layout comes from:
//  - instance_boxes: unit cubes in a MultiMesh (villages); worked out from the
//    instance's size.
//  - COLOR.a = 1: the mesh carries it (UV.x = metres along the grain, UV.y =
//    boards across, COLOR.r = sawn end, COLOR.g = a random number per piece,
//    COLOR.b = half the board width in metres).
//  - COLOR.a = 0.5: only the grain direction is given (COLOR.rgb).
//  - COLOR.a = 0.25: the same, for round logs: no seams.
//  - COLOR.a = 0: nothing given; planks run level along walls and floors.

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float band_lo = 0.014;
uniform float band_hi = 0.292;
uniform vec3 tint : source_color = vec3(1.0);
uniform float board_w = 0.26;
uniform float atlas_m = 3.4;
uniform float rough = 0.84;
uniform float bump = 1.0;
uniform bool instance_boxes = false;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec4 lay;      // u (m), v (boards), sawn end, seed
varying vec3 lay2;     // mode, board width (m), unused
varying vec3 grain;

float hash1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	lay = vec4(UV.x, UV.y, COLOR.r, COLOR.g);
	lay2 = vec3(COLOR.a * 4.0, COLOR.a > 0.75 ? max(COLOR.b * 0.5, 0.02) : board_w, 0.0);
	grain = COLOR.rgb * 2.0 - 1.0;
	if (instance_boxes) {
		vec3 sz = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		vec3 an = abs(NORMAL);
		int k = an.x > 0.5 ? 0 : (an.y > 0.5 ? 1 : 2);
		int l = (sz.x >= sz.y && sz.x >= sz.z) ? 0 : (sz.y >= sz.z ? 1 : 2);
		float seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (k == l) {
			int a = (k + 1) % 3;
			int b = (k + 2) % 3;
			if (max(sz[a], sz[b]) > 0.45) {
				// Too big to be the sawn end of one timber (the side of a
				// counter, a crate): it is boarded like the other faces.
				if (sz[b] > sz[a]) {
					int t = a;
					a = b;
					b = t;
				}
				float n = max(1.0, floor(sz[b] / board_w + 0.5));
				lay = vec4(VERTEX[a] * sz[a], (VERTEX[b] + 0.5) * n, 0.0, seed + 0.31);
				lay2 = vec3(4.0, sz[b] / n, 0.0);
			} else {
				lay = vec4(VERTEX[a] * sz[a], VERTEX[b] * sz[b], 1.0, seed);
				lay2 = vec3(4.0, board_w, 0.0);
			}
		} else {
			int o = 3 - k - l;
			float n = max(1.0, floor(sz[o] / board_w + 0.5));
			lay = vec4(VERTEX[l] * sz[l], (VERTEX[o] + 0.5) * n, 0.0, seed);
			lay2 = vec3(4.0, sz[o] / n, 0.0);
		}
	}
}

// One board's worth of grain: colour and a height for the bump.
vec4 board(float u, float vb, float bw, float seed, float seams, vec2 du, vec2 dv) {
	float idx = floor(vb);
	float fb = vb - idx;
	float h1 = hash1(idx * 7.13 + seed * 91.7);
	float h2 = hash1(idx * 3.71 + seed * 17.3 + 5.1);
	float h3 = hash1(idx * 1.93 + seed * 53.9 + 2.7);
	float slice = band_hi - band_lo;
	float bh = min(bw / atlas_m, slice * 0.8);
	vec2 auv = vec2(u / atlas_m + h1 * 3.0, band_lo + (slice - bh) * h2 + fb * bh);
	vec3 col = textureGrad(atlas, auv, vec2(du.x / atlas_m, dv.x * bh), vec2(du.y / atlas_m, dv.y * bh)).rgb;
	// Boards per pixel: from far off the seams and the board-to-board
	// differences are finer than a pixel and would only shimmer.
	float fine = max(length(dv), 0.0001);
	float near = clamp(1.0 - (fine - 0.10) / 0.30, 0.0, 1.0);
	float near2 = clamp(1.0 - (fine - 0.30) / 0.70, 0.0, 1.0);
	// No two boards quite the same.
	col *= mix(0.97, mix(0.84, 1.10, h3), near2);
	col = mix(col, col * vec3(1.05, 0.98, 0.90), h1 * 0.6 * near2);
	float hgt = dot(col, vec3(0.33)) * 0.5;
	if (seams > 0.5) {
		// Gap between boards.
		float de = min(fb, 1.0 - fb) * bw;
		float gap = 1.0 - smoothstep(0.003, 0.012, de);
		float bevel = 1.0 - smoothstep(0.0, 0.03, de);
		// Butt joints: here and there a board ends and the next begins.
		float len = 3.6;
		float ju = fract(u / len + h2 * 5.0) * len;
		float dj = min(ju, len - ju);
		float has_joint = step(0.42, h3);
		float joint = (1.0 - smoothstep(0.002, 0.009, dj)) * has_joint;
		// Two nails either side of it.
		vec2 np = vec2(abs(dj - 0.045), min(abs(fb - 0.24), abs(fb - 0.76)) * bw);
		float nail = (1.0 - smoothstep(0.006, 0.011, length(np))) * has_joint * step(0.10, bw);
		float dark = max(gap, joint) * near;
		col *= 1.0 - dark * 0.72;
		col *= 1.0 - bevel * 0.14 * near;
		// (All those gaps still darken the deck a little from afar.)
		col *= 1.0 - (1.0 - near) * 0.06;
		col = mix(col, vec3(0.10, 0.09, 0.09), nail * 0.85 * near);
		hgt -= (dark * 0.9 + bevel * 0.12 - nail * 0.25) * near;
	}
	return vec4(col, hgt);
}

// Sawn end: rings, mirrored so they never show a seam.
vec4 sawn(vec2 p) {
	vec2 t = abs(fract(p / 0.5 + 0.5) * 2.0 - 1.0);
	vec2 auv = vec2(0.418, 0.708) + (0.5 - t) * 0.118;
	vec3 col = textureLod(atlas, auv, 1.0).rgb;
	// The dark band's ends are darker too.
	col *= band_lo > 0.2 ? vec3(0.62, 0.56, 0.52) : vec3(1.0);
	return vec4(col * 0.94, dot(col, vec3(0.33)) * 0.5);
}

void fragment() {
	vec3 n = normalize(w_nrm);
	float mode = lay2.x;
	vec4 res;
	if (mode > 3.0) {
		if (lay.z > 0.5) {
			res = sawn(lay.xy);
		} else {
			res = board(lay.x, lay.y, lay2.y, lay.w, 1.0, vec2(dFdx(lay.x), dFdy(lay.x)), vec2(dFdx(lay.y), dFdy(lay.y)));
		}
	} else {
		vec3 l = vec3(1.0, 0.0, 0.0);
		if (mode > 0.5) {
			l = normalize(grain);
		} else if (abs(n.y) < 0.7) {
			l = normalize(cross(n, vec3(0.0, 1.0, 0.0)));
		}
		vec3 a = normalize(cross(l, abs(l.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 b = cross(l, a);
		float u = dot(w_pos, l);
		float pa = dot(w_pos, a);
		float pb = dot(w_pos, b);
		if (abs(dot(n, l)) > 0.8) {
			res = sawn(vec2(pa, pb));
		} else {
			float seams = (mode > 0.5 && mode < 1.5) ? 0.0 : 1.0;
			vec2 du = vec2(dFdx(u), dFdy(u));
			// Faces looking along `a` are laid out across `b`, and the other
			// way round; round logs blend between the two.
			float wa = abs(dot(n, a));
			float wb = abs(dot(n, b));
			float k = clamp((wa - wb) * 4.0 + 0.5, 0.0, 1.0);
			vec4 ra = board(u, pb / board_w, board_w, 0.0, seams, du, vec2(dFdx(pb), dFdy(pb)) / board_w);
			vec4 rb = board(u, pa / board_w, board_w, 0.37, seams, du, vec2(dFdx(pa), dFdy(pa)) / board_w);
			res = mix(rb, ra, k);
		}
	}
	ALBEDO = res.rgb * tint;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	// Bump from the height, no tangents needed.
	float h = res.a * 0.018 * bump;
	vec3 vn = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, vn);
	vec3 r2 = cross(vn, dpx);
	float det = dot(dpx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * vn - g);
}
