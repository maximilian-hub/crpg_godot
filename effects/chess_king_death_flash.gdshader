shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.22, 0.0, 0.0, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.08, 0.08, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(shadow_color.rgb, highlight_color.rgb, luminance), source.a);
}
