shader_type canvas_item;
// Terrain chunks. Sprites drawn with a marker alpha get cheap GPU animation, so the
// cached chunk draw lists never need a per-frame redraw:
//   alpha 254/255 -> wind sway (only the top edge of a sprite in the atlas sway shelf, UV.y == 0)
//   alpha 253/255 -> flame flicker
uniform float sway_strength = 1.0;
uniform float wind = 1.0;
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
	}
	COLOR = c;
}
