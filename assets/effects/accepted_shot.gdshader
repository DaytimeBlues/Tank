shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Original analytic blast/smoke card. No textures or gameplay state.
// One alpha-blended card per existing pool slot; no additive layers or lights.
uniform float age = 0.0;
uniform float life = 0.7;
uniform float variant = 0.0;
uniform float seed = 0.0;
uniform float confirmed_damage = 0.0;

float puff(vec2 p, vec2 center, vec2 shape) {
	float radius = length((p - center) / shape);
	return 1.0 - smoothstep(0.35, 1.0, radius);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float t = clamp(age / life, 0.0, 1.0);
	float contact = step(0.5, variant);
	float heat = 1.0 - smoothstep(0.025, mix(0.075, 0.20, contact), age);
	float flash = 1.0 - smoothstep(0.0, 0.045, age);
	// The hot core dies first; orange lobes survive briefly at an impact.
	float swirl = sin(p.x * 13.0 + seed + t * 3.0)
		* sin(p.y * 11.0 - seed * 0.7 - t * 4.0);
	float radius = length(p * vec2(1.0, 1.12)) + swirl * 0.075;
	float core = exp(-dot(p, p) * 19.0);
	float fire = (1.0 - smoothstep(0.18, 0.72, radius)) * heat;
	vec3 fire_color = mix(vec3(0.96, 0.20, 0.025), vec3(1.0, 0.69, 0.16), core);
	fire_color = mix(fire_color, vec3(1.0, 0.97, 0.82), core * flash);
	// Overlapping asymmetric puffs replace the previous smooth circular disc.
	// UV y points down; negative y is the rising side of the billboard.
	float spread = smoothstep(0.0, 0.65, t);
	vec2 q = p + vec2(swirl * 0.025, 0.0);
	float smoke = puff(q, vec2(0.0, 0.06), vec2(0.56, 0.49));
	smoke = max(smoke, puff(q, vec2(-0.27, -0.13 - spread * 0.10), vec2(0.40, 0.47)));
	smoke = max(smoke, puff(q, vec2(0.27, -0.18 - spread * 0.09), vec2(0.43, 0.44)));
	smoke = max(smoke, puff(q, vec2(-0.05, -0.37), vec2(0.40, 0.43)));
	float smoke_age = smoothstep(0.025, 0.14, age) * (1.0 - smoothstep(0.20, 1.0, t));
	// Erode to separated wisps as alpha falls, without a texture/noise fetch.
	float erosion = mix(1.0, smoothstep(-0.65, 0.50, swirl), smoothstep(0.35, 1.0, t));
	float smoke_alpha = smoke * smoke_age * erosion * mix(0.30, 0.54, contact);
	vec3 smoke_color = mix(vec3(0.19, 0.18, 0.16), vec3(0.43, 0.40, 0.34), t);
	smoke_color *= 0.92 + 0.12 * swirl;
	float fire_alpha = fire * 0.95;
	float alpha = fire_alpha + smoke_alpha * (1.0 - fire_alpha);
	ALBEDO = mix(smoke_color, fire_color, fire_alpha / max(alpha, 0.001));
	// Brief compact confirmation inside the existing card, not a new light/layer.
	float damage = clamp(confirmed_damage, 0.0, 1.0) * contact;
	float accent = damage * (1.0 - smoothstep(0.06, 0.20, age))
		* (1.0 - smoothstep(0.08, 0.34, length(p)));
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.98, 0.79), accent);
	alpha = max(alpha, accent * 0.95);
	ALPHA = alpha * (1.0 - smoothstep(0.88, 1.0, length(p)));
	// Vehicle loss is a server-confirmed terminal hit, never a health guess.
	// Build an upward pulse and rolling smoke inside this same pooled card.
	if (variant > 1.5) {
		float phase = clamp(age / life, 0.0, 1.0);
		float grow = smoothstep(0.02,0.66,age);
		// A sheet of pressure at the contact's foot; hot interior fades
		// before the denser upper roll, then erodes into separate streaks.
		float billow = sin(p.x*17.0+seed+age*1.8)*sin(p.y*16.0-seed-age*3.4);
		float grain = sin(p.x*38.0+p.y*11.0+seed)*sin(p.y*29.0-p.x*16.0);
		vec2 w=p+vec2(billow*.045+grain*.018,billow*.055+grain*.016);
		float base=puff(w,vec2(-.02,.39-.12*grow),vec2(.89,.24));
		float pillar=puff(w,vec2(.03,-.01-.18*grow),vec2(.41,.46));
		float shoulder=puff(w,vec2(-.23,-.14-.20*grow),vec2(.29,.29));
		float crest=puff(w,vec2(.18,-.26-.27*grow),vec2(.33,.29));
		float roll=max(pillar,max(shoulder,crest));
		float smoke=roll*smoothstep(.04,.18,age)*(1.0-smoothstep(.32,1.0,phase));
		float detail=.50+.27*billow+.22*grain;
		smoke*=mix(.72+.28*detail,smoothstep(.24,.76,detail),smoothstep(.20,.84,phase));
		float dust=base*(1.0-smoothstep(.25,.82,phase))*.72;
		float blast=puff(w,vec2(-.03,.18),vec2(.69,.30));
		float tongue=puff(w,vec2(.08,-.05),vec2(.25,.51));
		float flame=max(blast,tongue)*(.69+.31*detail)*(1.0-smoothstep(.055,.31,age));
		float white=puff(w,vec2(-.06,.20),vec2(.39,.20))*(1.0-smoothstep(.07,.17,age));
		float a=max(white,max(flame,max(smoke*.87,dust)));
		vec3 soot=mix(vec3(.12,.108,.095),vec3(.40,.365,.31),detail+.14*phase);
		vec3 col=mix(soot,vec3(.53,.42,.30),dust*(1.0-smoke));
		col=mix(col,mix(vec3(.88,.22,.025),vec3(1.0,.73,.19),detail),smoothstep(.10,.63,flame));
		col=mix(col,vec3(1.0,.98,.83),white);
		ALBEDO=col;
		ALPHA=a*(1.0-smoothstep(.91,1.0,length(p)));
	}
}