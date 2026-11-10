extends RefCounted
class_name Graphics

## Quality presets. ULTRA and HIGH use the Forward+ renderer's heavy hitters:
## SDFGI (ray-marched global illumination: light bounces into rooms, colour
## bleeds off walls), screen-space reflections and indirect light, volumetric
## fog with god rays, long soft shadows and temporal anti-aliasing. On the
## fallback OpenGL renderer the presets only scale shadows and draw distance.

const NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]


static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## How far trees and scatter stay visible, relative to the base ranges.
static func draw_scale(q: int) -> float:
	return [0.7, 0.9, 1.0, 1.2][clampi(q, 0, 3)]


## Upscaling choices: render the 3D scene smaller and let FSR 2 rebuild it.
const UPSCALE_NAMES := ["NATIVE", "FSR QUALITY", "FSR BALANCED", "FSR PERFORMANCE"]
const UPSCALE_SCALE := [1.0, 0.67, 0.59, 0.5]


static func apply(q: int, env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D, vp: Viewport, we: WorldEnvironment = null, upscale := 0) -> void:
	q = clampi(q, 0, 3)
	var fp := forward_plus()
	# Shadows.
	if sun != null:
		sun.directional_shadow_max_distance = [90.0, 140.0, 200.0, 260.0][q]
		sun.shadow_blur = [0.6, 1.0, 1.2, 1.4][q]
		sun.directional_shadow_split_1 = 0.07 if q >= 2 else 0.10
		sun.directional_shadow_split_2 = 0.18 if q >= 2 else 0.22
		sun.directional_shadow_split_3 = 0.42 if q >= 2 else 0.48
		# (A light size turns on contact-hardening shadows: costly, and the
		# blur already gives soft edges.)
		sun.light_angular_distance = 0.0
	# (An 8192 map cost a lot of GPU time for little gain over 4096.)
	RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 4096][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	if vp != null:
		var fsr2 := fp and upscale > 0
		# FSR 2 does its own temporal anti-aliasing.
		vp.use_taa = fp and q >= 2 and not fsr2
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if (q == 1 or (not fp and q >= 1)) and not fsr2 else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.msaa_3d = Viewport.MSAA_2X if (not fp and q >= 2) else Viewport.MSAA_DISABLED
		if fsr2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = UPSCALE_SCALE[clampi(upscale, 0, 3)]
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.77 if q == 0 else 1.0
		vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0][q]
	if env == null:
		return
	# Full SDFGI only on ULTRA: physically lit interiors, with eye adaptation
	# so dark rooms stay playable. HIGH uses screen-space indirect light.
	var gi := fp and q == 3
	if we != null:
		if fp and q >= 2:
			var ca := CameraAttributesPractical.new()
			ca.auto_exposure_enabled = true
			# Outdoors stays as authored; only dark interiors brighten.
			ca.auto_exposure_min_sensitivity = 100.0
			ca.auto_exposure_max_sensitivity = 900.0 if gi else 260.0
			ca.auto_exposure_scale = 0.3 if gi else 0.22
			ca.auto_exposure_speed = 2.5
			we.camera_attributes = ca
		else:
			we.camera_attributes = null
	env.sdfgi_enabled = gi
	if gi:
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 1.0
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.2
		env.sdfgi_cascade0_distance = 12.8
		env.sdfgi_energy = 2.4
		env.sdfgi_normal_bias = 1.1
		env.sdfgi_probe_bias = 1.1
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
		# Fewer rays over more frames: the same light, a fraction of the cost
		# per frame, and no spike when the cascades move with you.
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_16)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES)
		RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_8_FRAMES)
	env.ssao_enabled = fp and q >= 1
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM if q == 3 else RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 4, 50, 300)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW)
	env.ssil_enabled = fp and q >= 2
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = fp and q >= 2
	env.ssr_max_steps = 56 if q == 3 else 40
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	# Volumetric fog: light shafts through trees, haze in valleys.
	env.volumetric_fog_enabled = fp and q >= 2
	env.volumetric_fog_density = 0.0007
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.96)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 160.0 if q == 3 else 110.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	# With bounced light doing the work, the flat fill and sky ambient back off
	# so interiors get properly dark corners and sunlit floors.
	if fill != null:
		fill.light_energy = 0.12 if gi else 0.32
	env.glow_enabled = q >= 1
	env.glow_intensity = 0.6 if fp else 0.55
	env.glow_bloom = 0.05 if fp else 0.04
	env.adjustment_saturation = 1.1 if gi else 1.12
