shader_type canvas_item;
// Terrain chunks. Sprites drawn with a marker alpha get cheap GPU animation, so the
// cached chunk draw lists never need a per-frame redraw:
//   alpha 254/255 -> wind sway (only the top edge of a sprite in the atlas sway shelf, UV.y == 0)
//   alpha 253/255 -> flame flicker
//   alpha 252/255 -> grazing animal: the whole sprite shuffles and nods; blue 0.94..1.0 carries
//                    a per-animal phase (restored to 1.0 so the colour is unchanged)
uniform float sway_strength = 1.0;
uniform float wind = 1.0;
// Island health drives the land's colour: a sick island fades to dusty sepia, a thriving one is
// lush and saturated. 0 = health ~40 or less, 1 = health ~90+ (eased on the CPU).
uniform float vitality = 1.0;
varying float flicker;

void vertex() {
	flicker = 0.0;
	float a = COLOR.a;
	if (abs(a - 254.0 / 255.0) < 0.0015) {
		COLOR.a = 1.0;
		if (UV.y < 0.0005) {
			float ph = VERTEX.x * 0.071 + VERTEX.y * 0.043;
			VERTEX.x += (sin(TIME * 1.7 + ph) * 0.8 + sin(TIME * 0.63 + ph * 1.7) * 0.6) * 1.4 * sway_strength * wind;
		}
	} else if (abs(a - 252.0 / 255.0) < 0.0015) {
		COLOR.a = 1.0;
		float ph = clamp((COLOR.b - 0.94) / 0.06, 0.0, 1.0) * 6.2832;
		COLOR.b = 1.0;
		VERTEX.x += sin(TIME * 0.45 + ph) * 1.6 * sway_strength;
		VERTEX.y -= max(0.0, sin(TIME * 1.9 + ph * 3.0)) * 0.6 * sway_strength;
	} else if (abs(a - 253.0 / 255.0) < 0.0015) {
		COLOR.a = 1.0;
		flicker = 1.0;
		VERTEX.y += sin(TIME * 9.0 + VERTEX.x) * 0.6 * sway_strength;
	}
}

void fragment() {
	vec4 c = COLOR * texture(TEXTURE, UV);
	if (flicker > 0.5) {
		float f = 0.85 + 0.15 * sin(TIME * 13.0 + FRAGCOORD.x * 0.05) * sway_strength;
		c.rgb *= f;
	} else {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = vec3(l) + (c.rgb - vec3(l)) * mix(0.42, 1.10, vitality);
		c.rgb = mix(c.rgb, c.rgb * vec3(1.07, 0.95, 0.78), (1.0 - vitality) * 0.55);
		c.rgb *= mix(0.94, 1.03, vitality);
	}
	COLOR = c;
}
