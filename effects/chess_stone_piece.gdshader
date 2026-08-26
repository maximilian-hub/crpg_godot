shader_type canvas_item;
render_mode unshaded;

uniform vec4 dark_stone : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 light_stone : source_color = vec4(0.58, 0.59, 0.62, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 sampled = texture(TEXTURE, UV) * COLOR;
	float luminance = dot(sampled.rgb, vec3(0.299, 0.587, 0.114));
	float stepped = floor(luminance * 5.0) / 4.0;
	vec3 stone = mix(dark_stone.rgb, light_stone.rgb, clamp(stepped, 0.0, 1.0));
	COLOR = vec4(stone, sampled.a * opacity);
}

