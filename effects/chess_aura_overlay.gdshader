shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.68, 1.0);
uniform vec4 accent_color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;
uniform float outline_intensity : hint_range(0.0, 2.0) = 0.9;
uniform float interior_intensity : hint_range(0.0, 2.0) = 0.45;
uniform float motion_speed : hint_range(0.0, 12.0) = 3.0;
uniform float elapsed = 0.0;
uniform float silhouette_fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 silhouette_fill_color : source_color = vec4(1.0);

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float source_alpha = texture(TEXTURE, UV).a;
	vec2 step_size = TEXTURE_PIXEL_SIZE * max(outline_width, 1.0);
	float nearby_alpha = 0.0;
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(step_size.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(step_size.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, step_size.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(0.0, step_size.y)).a);
	float outline = max(nearby_alpha - source_alpha, 0.0) * outline_intensity;

	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 cell = floor(pixel / 3.0);
	float rising_band = fract((cell.y * 0.17) + elapsed * motion_speed * 0.12);
	float checker = mod(cell.x + cell.y, 2.0);
	float spark = step(0.70 - power * 0.25, hash21(cell + floor(elapsed * motion_speed)));
	float interior = source_alpha * spark * mix(0.55, 1.0, checker) * rising_band * interior_intensity;

	vec4 aura = mix(core_color, accent_color, clamp(rising_band + checker * 0.2, 0.0, 1.0));
	float aura_alpha = clamp((outline + interior) * power, 0.0, 1.0);
	aura = mix(aura, silhouette_fill_color, source_alpha * silhouette_fill);
	aura.a = max(aura_alpha, source_alpha * silhouette_fill * silhouette_fill_color.a);
	COLOR = aura;
}
