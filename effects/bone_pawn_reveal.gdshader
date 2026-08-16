shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 sampled = texture(TEXTURE, UV) * COLOR;
	float reveal_mask = 1.0 - smoothstep(reveal, reveal + 0.035, UV.y);
	sampled.a *= reveal_mask;
	COLOR = sampled;
}
