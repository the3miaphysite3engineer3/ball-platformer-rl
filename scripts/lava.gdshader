// by qkrooz and Amy, CC0
// Original by qkrooz is https://godotshaders.com/shader/stylized-lava/

shader_type spatial;
render_mode shadows_disabled;

uniform vec4 a_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 b_color : source_color = vec4(0.275, 0.031, 0.035, 1.0);
uniform vec4 c_color : source_color = vec4(0.906, 0.0, 0.043, 1.0);
uniform vec4 d_color : source_color = vec4(0.996, 0.604, 0.0, 1.0);

uniform float a_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float b_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float c_roughness : hint_range(0.0, 1.0) = 0.25;
uniform float d_roughness : hint_range(0.0, 1.0) = 0.0;

uniform float speed : hint_range(0.0, 5.0) = 0.25;
uniform float scale : hint_range(0.1, 40.0) = 5.0;
uniform float sharpness : hint_range(1.0, 50.0) = 8.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.15;
uniform float crust_emission : hint_range(0.0, 1.0) = 0.0;
uniform float emission_intensity : hint_range(0.0, 10.0) = 10.0;

varying vec3 world_position;
varying vec3 world_normal;

float mix4(float a, float b, float c, float d, float t) {
	t = clamp(t, 0.0, 1.0);

	if (t < 1.0 / 3.0) {
		return mix(a, b, t * 3.0);
	} else if (t < 2.0 / 3.0) {
		return mix(b, c, t * 3.0 - 1.0);
	} else {
		return mix(c, d, t * 3.0 - 2.0);
	}
}

vec2 mix4(vec2 a, vec2 b, vec2 c, vec2 d, float t) {
	t = clamp(t, 0.0, 1.0);

	if (t < 1.0 / 3.0) {
		return mix(a, b, t * 3.0);
	} else if (t < 2.0 / 3.0) {
		return mix(b, c, t * 3.0 - 1.0);
	} else {
		return mix(c, d, t * 3.0 - 2.0);
	}
}

vec3 mix4(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	t = clamp(t, 0.0, 1.0);

	if (t < 1.0 / 3.0) {
		return mix(a, b, t * 3.0);
	} else if (t < 2.0 / 3.0) {
		return mix(b, c, t * 3.0 - 1.0);
	} else {
		return mix(c, d, t * 3.0 - 2.0);
	}
}

vec4 mix4(vec4 a, vec4 b, vec4 c, vec4 d, float t) {
	t = clamp(t, 0.0, 1.0);

	if (t < 1.0 / 3.0) {
		return mix(a, b, t * 3.0);
	} else if (t < 2.0 / 3.0) {
		return mix(b, c, t * 3.0 - 1.0);
	} else {
		return mix(c, d, t * 3.0 - 2.0);
	}
}

float triplanar_map(float x, float y, float z, vec3 n) {
	n = n * n;
	return (x * n.x + y * n.y + z * n.z) / (n.x + n.y + n.z);
}

vec2 triplanar_map(vec2 x, vec2 y, vec2 z, vec3 n) {
	n = n * n;
	return (x * n.x + y * n.y + z * n.z) / (n.x + n.y + n.z);
}

vec3 triplanar_map(vec3 x, vec3 y, vec3 z, vec3 n) {
	n = n * n;
	return (x * n.x + y * n.y + z * n.z) / (n.x + n.y + n.z);
}

vec4 triplanar_map(vec4 x, vec4 y, vec4 z, vec3 n) {
	n = n * n;
	return (x * n.x + y * n.y + z * n.z) / (n.x + n.y + n.z);
}

vec2 random2D(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float voronoiIQ(vec2 _pos) {
	float _time = TIME * speed;
	_pos.y += _time;
	_pos.x += sin(_time);

	vec2 p = floor(_pos);
	vec2 f = fract(_pos);
	float res = 0.0;
	
	// Clamp the sharpness to avoid extreme behavior.
	float sharp = clamp(sharpness, 1.0, 50.0);
	
	// Sum contributions from neighboring cells.
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 pnt = random2D(p + b);
			pnt = 0.5 + 0.5 * sin(_time + 6.2831 * pnt);
			vec2 r = vec2(b) - f + pnt;
			float d = dot(r, r);
			res += exp(-sharp * d);
		}
	}
	
	// Ensure we never take the log of zero.
	res = max(res, 1e-6);
	
	// Calculate the final value. Optionally, clamp the result.
	float result = -(1.0 / sharp) * log(res);
	return clamp(result, 0.0, 1.0);
}

vec3 bump_normal(vec3 position, vec3 normal, float height, float strength) {
	vec3 dpdx = dFdx(position);
	vec3 dpdy = dFdy(position);

	float dhdx = dFdx(height);
	float dhdy = dFdy(height);

	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);

	float det = dot(dpdx, r1);

	// Avoid division by zero at degenerate projections.
	if (abs(det) < 1e-6) {
		return normal;
	}

	vec3 gradient = (r1 * dhdx + r2 * dhdy) / det;

	return normalize(normal - strength * gradient);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 pos = world_position * scale;
	vec3 n = normalize(world_normal);

	float voronoi_x = voronoiIQ(pos.yz);
	float voronoi_y = voronoiIQ(pos.xz);
	float voronoi_z = voronoiIQ(pos.xy);

	float voronoi_value = triplanar_map(
		voronoi_x,
		voronoi_y,
		voronoi_z,
		n
	);

	vec4 final_color = mix4(
		a_color, b_color, c_color, d_color,
		voronoi_value
	);

	float final_roughness = mix4(
		a_roughness, b_roughness,
		c_roughness, d_roughness,
		voronoi_value
	);

	ALBEDO = final_color.rgb;
	float hot_mask = smoothstep(0.25, 0.8, voronoi_value);
	EMISSION = final_color.rgb * emission_intensity
		* mix(crust_emission, 1.0, hot_mask);
	ROUGHNESS = final_roughness;

	// VERTEX and NORMAL here are in view space.
	NORMAL = bump_normal(
		VERTEX,
		normalize(NORMAL),
		voronoi_value,
		bump_strength
	);
}
