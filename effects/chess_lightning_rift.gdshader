shader_type canvas_item;
render_mode unshaded;

// The geometry is only a window. FRAGCOORD anchors one infinite checkerboard
// to the screen, so changing the rift silhouette never moves its contents.
uniform float checker_size : hint_range(1.0, 64.0) = 8.0;
uniform float visible_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / max(checker_size, 1.0));
	float white_square = mod(cell.x + cell.y, 2.0);
	float source_alpha = COLOR.a;
	COLOR = vec4(vec3(white_square), source_alpha * visible_strength);
}
