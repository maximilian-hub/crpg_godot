shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.29, 0.18, 0.11, 1.0);
uniform sampler2D material_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = false;
uniform float texture_scale : hint_range(0.25, 8.0) = 1.0;
uniform float grain_tightness : hint_range(0.15, 2.0) = 1.0;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.8;
uniform float brightness : hint_range(0.4, 1.4) = 1.0;
uniform float procedural_detail : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(
		mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), fraction.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), fraction.x),
		fraction.y
	);
}

void fragment() {
	vec2 sample_uv = UV * vec2(texture_scale, grain_tightness);
	vec3 color = base_color.rgb;
	if (use_texture) color = mix(color, texture(material_texture, sample_uv).rgb, texture_strength);
	float wandering = noise21(vec2(sample_uv.x * 0.7, sample_uv.y * 2.0)) * 0.35;
	float grain = sin((sample_uv.y * 5.0 + wandering + sin(sample_uv.x * 0.9) * 0.12) * 18.0) * 0.5 + 0.5;
	color *= mix(0.92, 1.06, grain * procedural_detail);
	COLOR = vec4(color * brightness, base_color.a);
}
