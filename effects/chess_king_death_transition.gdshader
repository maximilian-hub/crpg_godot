shader_type canvas_item;
render_mode unshaded;

uniform vec4 red_shadow : source_color = vec4(0.22, 0.0, 0.0, 1.0);
uniform vec4 red_highlight : source_color = vec4(1.0, 0.08, 0.08, 1.0);
uniform vec4 dark_stone : source_color = vec4(0.18, 0.19, 0.22, 1.0);
uniform vec4 light_stone : source_color = vec4(0.58, 0.59, 0.62, 1.0);
uniform float stone_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 red = mix(red_shadow.rgb, red_highlight.rgb, luminance);
	float stepped = floor(luminance * 5.0) / 4.0;
	vec3 stone = mix(dark_stone.rgb, light_stone.rgb, clamp(stepped, 0.0, 1.0));
	COLOR = vec4(mix(red, stone, stone_progress), source.a);
}
