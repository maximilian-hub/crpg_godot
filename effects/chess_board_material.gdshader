shader_type canvas_item;

uniform vec4 light_color : source_color = vec4(0.85, 0.78, 0.63, 1.0);
uniform vec4 dark_color : source_color = vec4(0.50, 0.38, 0.28, 1.0);
uniform sampler2D light_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D dark_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_light_texture = false;
uniform bool use_dark_texture = false;
uniform vec2 board_dimensions = vec2(8.0, 8.0);
uniform float texture_scale : hint_range(0.25, 8.0) = 1.0;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.7;
uniform float light_brightness : hint_range(0.4, 1.2) = 1.0;
uniform float variation_strength : hint_range(0.0, 0.25) = 0.06;
uniform float procedural_detail : hint_range(0.0, 1.0) = 0.35;
uniform float seam_width : hint_range(0.0, 0.08) = 0.012;
uniform vec4 seam_color : source_color = vec4(0.12, 0.08, 0.06, 0.45);

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point) {
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
	vec2 grid_uv = UV * board_dimensions;
	vec2 cell = floor(min(grid_uv, board_dimensions - vec2(0.0001)));
	vec2 local_uv = fract(grid_uv);
	float seed = hash21(cell);
	if (seed > 0.5) local_uv.x = 1.0 - local_uv.x;
	if (hash21(cell + 19.0) > 0.5) local_uv.y = 1.0 - local_uv.y;
	vec2 sample_uv = (local_uv + vec2(hash21(cell + 7.0), hash21(cell + 13.0))) * texture_scale;
	bool light_square = mod(cell.x + cell.y, 2.0) < 1.0;
	vec4 base = light_square ? light_color : dark_color;
	vec4 sampled = base;
	if (light_square && use_light_texture) sampled = texture(light_texture, sample_uv);
	if (!light_square && use_dark_texture) sampled = texture(dark_texture, sample_uv);
	float texture_mix = (light_square && use_light_texture) || (!light_square && use_dark_texture) ? texture_strength : 0.0;
	vec3 color = mix(base.rgb, sampled.rgb, texture_mix);
	color *= light_square ? light_brightness : 1.0;
	float broad_noise = value_noise(sample_uv * 2.1 + cell * 0.37);
	float vein = pow(1.0 - abs(sin((sample_uv.x * 1.7 + sample_uv.y * 0.8 + broad_noise * 1.8) * 3.14159)), 9.0);
	color *= 1.0 + (seed - 0.5) * variation_strength * 2.0;
	color = mix(color, color * (light_square ? 0.78 : 1.18), vein * procedural_detail * 0.28);
	float edge_distance = min(min(local_uv.x, 1.0 - local_uv.x), min(local_uv.y, 1.0 - local_uv.y));
	float seam = 1.0 - smoothstep(0.0, seam_width, edge_distance);
	COLOR = vec4(mix(color, seam_color.rgb, seam * seam_color.a), base.a);
}
