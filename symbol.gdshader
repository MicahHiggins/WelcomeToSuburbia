shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);

uniform float glow_strength : hint_range(0.0, 25.0) = 10.0; // higher = more bloom
uniform float base_alpha : hint_range(0.0, 1.0) = 0.75;
uniform float base_brightness : hint_range(0.0, 2.0) = 0.45;

uniform float flicker_amount : hint_range(0.0, 1.0) = 0.15;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;  // new
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.2;   // new

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	float r = clamp(reveal, 0.0, 1.0);

	vec3 out_albedo = vec3(0.0);
	vec3 out_emission = vec3(0.0);
	float out_alpha = 0.0;

	if (r > 0.001) {
		float t = TIME;

		// tiny static flicker
		float flick = mix(1.0, 0.85 + 0.15 * hash(UV * 50.0 + t), flicker_amount * r);

		// smooth pulse so the glow feels “alive”
		float pulse = 1.0 + (sin(t * pulse_speed) * 0.5 + 0.5) * pulse_amount * r;

		// solid visible paint (slightly transparent)
		vec3 base_col = glow_color.rgb * base_brightness;
		out_albedo = base_col * r;

		// strong emission for bloom
		out_emission = glow_color.rgb * glow_strength * r * flick * pulse;

		out_alpha = r * base_alpha;
	}

	ALBEDO = out_albedo;
	EMISSION = out_emission;
	ALPHA = out_alpha;
}