shader_type spatial;
render_mode unshaded;

uniform float uv_reveal : hint_range(0.0, 1.0) = 0.0;

uniform vec3 base_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 uv_glow_color : source_color = vec3(0.70, 0.25, 1.00);
uniform float glow_strength : hint_range(0.0, 10.0) = 3.0;

// Give these a real texture in the inspector.
// If you don't have one yet, use a 1x1 white texture for albedo and
// a 1x1 white OR mask texture for uv_mask_tex.
uniform sampler2D albedo_tex : source_color;
uniform sampler2D uv_mask_tex : source_color; // white = ink, black = nothing

void fragment() {
	vec2 uv = UV;

	vec3 base_col = base_tint * texture(albedo_tex, uv).rgb;

	float mask = texture(uv_mask_tex, uv).r;

	float r = clamp(uv_reveal, 0.0, 1.0);
	float ink = mask * smoothstep(0.15, 1.0, r);

	ALBEDO = base_col;
	EMISSION = uv_glow_color * (ink * glow_strength);
	ALPHA = 1.0;
}