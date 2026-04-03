shader_type spatial;

uniform sampler2D flesh_tex : source_color;
uniform sampler2D flesh_normal : hint_normal;

uniform float uv_scale = 1.5;
uniform float offset_amount = 8.0;
uniform float tint_strength = 0.35;
uniform float normal_strength = 1.0;

instance uniform vec2 block_offset = vec2(0.0, 0.0);
instance uniform float block_rotation = 0.0;
instance uniform vec3 block_tint = vec3(1.0, 1.0, 1.0);

vec2 rotate_uv(vec2 uv, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	uv -= vec2(0.5);
	uv = vec2(
		c * uv.x - s * uv.y,
		s * uv.x + c * uv.y
	);
	uv += vec2(0.5);
	return uv;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	uv = rotate_uv(uv, block_rotation);
	uv += block_offset * offset_amount;

	vec4 albedo_tex = texture(flesh_tex, uv);
	vec3 normal_tex = texture(flesh_normal, uv).rgb;

	ALBEDO = albedo_tex.rgb * mix(vec3(1.0), block_tint, tint_strength);
	NORMAL_MAP = normal_tex;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 1.0;
}