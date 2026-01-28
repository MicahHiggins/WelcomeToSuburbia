shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture;

uniform vec3 tint_color = vec3(1.0, 0.2, 0.1); // reddish
uniform float max_strength = 0.35;            // max tint amount
uniform float start = 0.90;                   // when it begins (dot threshold)
uniform float end = 0.995;                    // when it's full strength

// how much you're looking at the sun (0..1)
uniform float sun_focus = 0.0;

void fragment() {
    vec4 col = texture(screen_tex, SCREEN_UV);

    // Map sun_focus into a smooth 0..1 strength
    float t = smoothstep(start, end, sun_focus) * max_strength;

    // Optional: tint mostly bright areas (glare-like)
    float luma = dot(col.rgb, vec3(0.2126, 0.7152, 0.0722));
    float highlight_mask = smoothstep(0.6, 0.95, luma); // tweak thresholds

    float strength = t * highlight_mask;

    col.rgb = mix(col.rgb, tint_color, strength);
    COLOR = col;
}


//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
