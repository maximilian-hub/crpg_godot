shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.24, 0.20, 0.18, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.93, 0.76, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	// Expand the authored Black palette's compact value range into ivory while
	// preserving its internal shading and source alpha.
	float palette_position = smoothstep(0.015, 0.34, luminance);
	COLOR = vec4(mix(shadow_color.rgb, highlight_color.rgb, palette_position), source.a);
}
