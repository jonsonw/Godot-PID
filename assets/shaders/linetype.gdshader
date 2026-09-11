shader_type canvas_item;
render_mode blend_mix;

// G-PID Linetype shader (ported from Godot-CAD/Shaders/Linetype.gdshader).
// G-PID 线型着色器（移植自 Godot-CAD/Shaders/Linetype.gdshader）。
//
// Dashes a Line2D along its length using a repeating on/off pattern scaled by
// linetype_scale (the global LTSCALE). Even indices = ink, odd = gap (discarded).
// 沿 Line2D 长度用「划/空」循环图案做虚线；偶数索引 = 有墨，奇数 = 空白（discard）。
// Works on a Line2D because Godot supplies UV.x running 0..1 along the polyline.
// 依赖 Line2D 提供的 UV.x（沿折线 0..1）。

uniform float pattern[20];
uniform int pattern_count;
uniform float linetype_scale = 1.0;
uniform float line_length = 100.0;
uniform vec4 color : source_color;

void fragment() {
	COLOR = color;

	if (pattern_count > 0) {
		float dist = UV.x * line_length;

		float total_pattern_len = 0.0;
		for (int i = 0; i < pattern_count; i++) {
			total_pattern_len += pattern[i] * linetype_scale;
		}

		if (total_pattern_len > 0.001) {
			float pos = mod(dist, total_pattern_len);
			float current_accum = 0.0;

			for (int i = 0; i < pattern_count; i++) {
				float segment_len = pattern[i] * linetype_scale;
				if (pos < current_accum + segment_len) {
					if (i % 2 != 0) {
						discard;
					}
					break;
				}
				current_accum += segment_len;
			}
		}
	}
}
