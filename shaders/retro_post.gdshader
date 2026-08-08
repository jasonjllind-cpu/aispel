shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float color_levels = 12.0;
uniform float dither_strength = 0.035;
uniform float contrast = 1.12;
uniform float saturation = 1.12;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0 - 0.5;
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col += bayer4(FRAGCOORD.xy) * dither_strength;
	col = floor(clamp(col, 0.0, 1.0) * color_levels) / color_levels;
	COLOR = vec4(col, 1.0);
}
