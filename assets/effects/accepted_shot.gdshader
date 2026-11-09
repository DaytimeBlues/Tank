shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Original analytic blast/smoke card. No texture, external effect code or hit logic.
uniform float age = 0.0;
uniform float life = 0.7;
uniform float variant = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float t = clamp(age / life, 0.0, 1.0);
	float hot_time = variant < 0.5 ? 0.075 : 0.11;
	float heat = 1.0 - smoothstep(0.0, hot_time, age);
	float lobes = sin(p.x * 12.0 + seed) * sin(p.y * 10.0 - seed * 0.7);
	float r = length(p * vec2(1.0, 1.10)) + lobes * 0.07;
	float core = exp(-r * r * 8.0);
	float flame = (1.0 - smoothstep(0.22, 0.83, r)) * heat;
	vec3 hot_color = mix(vec3(1.0, 0.32, 0.045), vec3(1.0, 0.94, 0.71), core);
	float smoke_r = length(p * vec2(0.94, 1.08)) + lobes * 0.10;
	float smoke = (1.0 - smoothstep(0.24, 0.96, smoke_r));
	float smoke_age = smoothstep(0.015, 0.12, age) * (1.0 - smoothstep(0.25, 1.0, t));
	float opacity = max(flame * 0.94, smoke * smoke_age * (variant < 0.5 ? 0.32 : 0.62));
	vec3 smoke_color = mix(vec3(0.13, 0.14, 0.13), vec3(0.26, 0.24, 0.20), core * 0.4);
	ALBEDO = mix(smoke_color, hot_color, heat);
	ALPHA = opacity * (1.0 - smoothstep(0.85, 1.0, r));
}
