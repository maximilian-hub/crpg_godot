shader_type canvas_item;

uniform vec4 flat_color : source_color = vec4(0.09, 0.07, 0.11, 1.0);
uniform sampler2D surface_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float texture_scale : hint_range(0.25, 8.0) = 1.0;
uniform float texture_strength : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.4, 1.4) = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec3 base = flat_color.rgb;
	vec3 sampled = use_texture ? texture(surface_texture, UV * texture_scale).rgb : base;
	vec3 color = mix(base, sampled, use_texture ? texture_strength : 0.0);
	COLOR = vec4(color * tint.rgb * brightness, flat_color.a);
}
