// Wisp's mobile terrain shader, for phones like the Galaxy A16 (Mali-G57 MC2), where
// Terrain3D's standard shader runs at 5 fps and its lightweight one at ~25 in the game.
// Built on Terrain3D's lightweight shader (MIT, Tokisan Games): same vertex stage and
// clipmap, but the control map is decoded once per vertex into weights for the four
// layers (grass, dirt, rock, sand) and blended between vertices, so each pixel reads only
// the layers present plus one normal map, instead of 4 control reads and an albedo and a
// normal per layer. Adds a cheap two-tone macro variation and the game's hemisphere light.
// Supports up to 4 texture layers.
shader_type spatial;
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_lambert,specular_schlick_ggx,skip_vertex_transform;

/* This is an example stripped down shader with maximum performance in mind.
 * Only Autoshader/Base/Over/Blend/Holes/Colormap are supported.
 * All terrain normal calculations take place in vetex().
 *
 * Control map indices are processed such that each ID only requires reading ONCE.
 * The following features: projection, detiling, and paintable rotation / scale
 * cannot work with this method, without the additional samples required for blending
 * between same ID textures with different values across indices.
 */

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2
#define COLOR_MAP vec4(1.0, 1.0, 1.0, 0.5)
#define DIV_255 0.003921568627450 // 1. / 255.

// Inline Functions
#define DECODE_BLEND(control) float(control >> 14u & 0xFFu) * DIV_255
#define DECODE_AUTO(control) bool(control & 0x1u)
#define DECODE_BASE(control) int(control >> 27u & 0x1Fu)
#define DECODE_OVER(control) int(control >> 22u & 0x1Fu)
#define DECODE_HOLE(control) bool(control >>2u & 0x1u)

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1./_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1./region_size
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// Public uniforms
uniform bool enable_texturing = true;
uniform float blend_sharpness : hint_range(0, 1) = 0.5;
uniform bool flat_terrain_normals = false;
// Autoshader
uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;
// Macro Variation
uniform bool enable_macro_variation = true;
uniform vec3 macro_variation1 : source_color = vec3(1.);
uniform vec3 macro_variation2 : source_color = vec3(1.);
uniform float macro_variation_slope : hint_range(0., 1.)  = 0.333;
uniform highp sampler2D noise_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float noise1_scale : hint_range(0.001, 1.) = 0.04; // Used for macro variation 1. Scaled up 10x
uniform float noise1_angle : hint_range(0, 6.283) = 0.;
uniform vec2 noise1_offset = vec2(0.5);
uniform float noise2_scale : hint_range(0.001, 1.) = 0.076; // Used for macro variation 2. Scaled up 10x

// Varyings & Types
varying vec3 v_normal;
varying vec4 v_weights;
uniform float normal_distance = 45.0;
uniform float macro_scale = 0.018;
uniform vec3 macro_dark : source_color = vec3(0.86, 0.9, 0.82);
uniform vec3 macro_light : source_color = vec3(1.06, 1.04, 0.96);
varying vec3 v_vertex;
varying mat3 TBN;

////////////////////////
// Vertex
////////////////////////

// Takes in world space XZ (UV) coordinates & search depth (only applicable for background mode none)
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

// Takes in descaled (world_space / region_size) world to region space XZ (UV2) coordinates, returns vec3 with:
// XY: (0. to 1.) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
vec3 get_index_uv(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int layer_index = _region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1;
	return vec3(uv2 - _region_locations[layer_index], float(layer_index));
}

void vertex() {
	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance to vertex on flat plane
	float v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing + 1e-6) ? // LOD0 or not
		// Shift from regular to symetric
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		// Symetric shift
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in world space. Values are 0 to _region_size within regions
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = DECODE_HOLE(control);
	// Layer weights from this vertex's control: base and overlay by the blend value
	{
		float b = DECODE_BLEND(control);
		ivec4 ids = ivec4(0, 1, 2, 3);
		v_weights = vec4(equal(ids, ivec4(DECODE_BASE(control)))) * (1.0 - b) + vec4(equal(ids, ivec4(DECODE_OVER(control)))) * b;
	}

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z == -1))) {
		v_vertex.x = 0. / 0.;
	} else {
		// Set final vertex height & calculate vertex normals. 3 lookups
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r,texelFetch(_height_maps, uv_b, 0).r,vertex_lerp);
		v_vertex.y = h;

		// Vertex normals
		float u = mix(texelFetch(_height_maps, get_index_coord(start_pos + vec2(1,0), VERTEX_PASS), 0).r,
			texelFetch(_height_maps, get_index_coord(end_pos + vec2(1,0), VERTEX_PASS), 0).r, vertex_lerp);
		float v = mix(texelFetch(_height_maps, get_index_coord(start_pos + vec2(0,1), VERTEX_PASS), 0).r,
			texelFetch(_height_maps, get_index_coord(end_pos + vec2(0,1), VERTEX_PASS), 0).r, vertex_lerp);

		v_normal = normalize(vec3(h - u, _vertex_spacing, h - v));
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;

	// Apply terrain normals
	vec3 w_tangent = normalize(cross(v_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(v_normal, w_tangent));
	TBN = mat3(w_tangent, w_binormal, v_normal);

	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(w_binormal, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(w_tangent, 0.0)).xyz);
}

////////////////////////
// Fragment
////////////////////////

void fragment() {
	// Terrain3D injects code (e.g. the editor's brush) that expects these
	vec2 uv = UV;
	vec2 uv2 = UV2;
	vec2 wuv = v_vertex.xz;
	vec4 w = max(v_weights, vec4(0.0));
	float cam_dist = length(v_vertex - _camera_pos);
	vec4 acc = vec4(0.0);
	float total = 0.0;
	float best = -1.0;
	int best_id = 0;
	vec2 best_uv = vec2(0.0);
	for (int id = 0; id < 4; id++) {
		float wi = w[id];
		if (wi > 0.015) {
			vec2 uvi = wuv * (_texture_uv_scale_array[id] * 0.5) + 0.5;
			vec4 alb = texture(_texture_array_albedo, vec3(uvi, float(id)));
			alb.rgb *= _texture_color_array[id].rgb;
			// Height blend: the higher texture (stones, tufts) wins where layers meet
			float hw = wi * (0.35 + alb.a);
			hw *= hw * hw;
			acc += alb * hw;
			total += hw;
			if (hw > best) {
				best = hw;
				best_id = id;
				best_uv = uvi;
			}
		}
	}
	vec4 albedo_height = acc / max(total, 1e-5);
	// One normal map, the strongest layer's, and only near the camera
	vec4 normal_rough = vec4(0.5, 0.5, 1.0, 0.85);
	float nd = 0.0;
	if (cam_dist < normal_distance) {
		normal_rough = texture(_texture_array_normal, vec3(best_uv, float(best_id)));
		nd = _texture_normal_depth_array[best_id] * (1.0 - smoothstep(normal_distance * 0.6, normal_distance, cam_dist));
	}
	// Macro variation: big soft patches, so tiling doesn't read from a distance
	float m = texture(noise_texture, wuv * macro_scale).r;
	vec3 macrov = mix(macro_dark, macro_light, m);
	ALBEDO = albedo_height.rgb * macrov;
	ROUGHNESS = clamp(normal_rough.a, 0.0, 1.0);
	SPECULAR = 0.2;
	NORMAL_MAP = normal_rough.rgb;
	NORMAL_MAP_DEPTH = nd;
	AO = mix(0.75, 1.0, albedo_height.a);
	AO_LIGHT_AFFECT = 0.4;
	EMISSION = ALBEDO * mix(hemi_ground, hemi_sky, 0.5 * v_normal.y + 0.5) * AO;
}
