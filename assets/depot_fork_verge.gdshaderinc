// One broad dry headland on the Depot side of the west landing. Packed
// road cores and the entire bridge footprint retain their original finish.
vec3 depot_fork_verge(vec3 soil, vec2 p, float road_dist, float broad, float fine) {
	if (p.x <= -118.0 || p.x >= -41.0 || p.y <= -130.0 || p.y >= -79.0) {
		return soil;
	}
	float u = -70.0-p.x;
	float bend = max(0.0,u) + 1.25*exp(-abs(u)*.27);
	float reference_z = -80.0-.8*bend;
	float side = (reference_z-p.y) * mix(1.0,.781,smoothstep(-4.0,6.0,u));
	float contour = noise(p*vec2(.095,.13)+vec2(4.0,15.0))-.5;
	float lobe = .5+.5*sin(u*.113+.9);
	float width = 18.0 + 9.0*lobe + 3.5*sin(u*.23) + 4.8*contour;
	float field = smoothstep(4.5,8.1,side+contour*3.8)*
		(1.0-smoothstep(width-5.0,width+1.0,side));
	float edge = smoothstep(-118.0,-106.0,p.x)*(1.0-smoothstep(-52.0,-41.0,p.x));
	edge *= smoothstep(-130.0,-123.0,p.y);
	float clear = smoothstep(5.7,8.3,road_dist)*
		smoothstep(13.0,16.0,length(p-vec2(-120.0,-120.0)));
	// Warm mown grass, broad pale wakes and threadlike stubble. No dark
	// inner rail or wheel stripe; the local grass clumps supply the relief.
	float dry = smoothstep(.22,.81,.63*noise(p*vec2(.09,.15))+.37*broad);
	float stalk = smoothstep(.34,.70,noise(p*vec2(.48,1.28))+contour*.26);
	vec3 hay = mix(vec3(.385,.408,.222),vec3(.585,.537,.307),.12+.49*dry+.33*stalk);
	vec3 ground = hay*(.93+.09*broad+.07*fine);
	return mix(soil,ground,edge*clear*field*.95);
}
