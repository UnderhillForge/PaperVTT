extends Node
class_name TimeOfDayLighting

@export var sky_3d: NodePath
@export var directional_light: NodePath
@export var world_environment: NodePath
@export var post_process_canvas: NodePath

@export var afternoon_start_hour: float = 10.0
@export var afternoon_end_hour: float = 16.0
@export var day_start_hour: float = 7.0
@export var day_end_hour: float = 19.0

@export var afternoon_sun_energy_min: float = 1.8
@export var afternoon_sun_energy_max: float = 2.5
@export var night_moon_energy_min: float = 0.15
@export var night_moon_energy_max: float = 0.4

@export var ambient_energy_night: float = 0.35
@export var ambient_energy_day: float = 0.58
@export var ambient_day_color: Color = Color(1.0, 0.95, 0.85, 1.0)
@export var ambient_night_color: Color = Color(0.50, 0.56, 0.70, 1.0)

var sky_node: Node = null
var sun_light: DirectionalLight3D = null
var env_node: WorldEnvironment = null
var postfx_node: CanvasLayer = null

var _override_enabled: bool = false
var _override_color: Color = Color(1.0, 0.95, 0.86, 1.0)
var _override_energy: float = 2.2
var _override_saturation: float = 1.0
var _override_tint_strength: float = 0.65
var _override_blend: float = 0.0

var _weather_global_intensity: float = 1.0
var _weather_stacking_enabled: bool = false
var _weather_channels: Dictionary = {
	"rain": 0.0,
	"snow": 0.0,
	"foggy": 0.0,
	"stormy": 0.0,
}
var _current_weather: String = "normal"


func _ready() -> void:
	sky_node = get_node_or_null(sky_3d)
	sun_light = get_node_or_null(directional_light) as DirectionalLight3D
	env_node = get_node_or_null(world_environment) as WorldEnvironment
	postfx_node = get_node_or_null(post_process_canvas) as CanvasLayer


func set_lighting_override(enabled: bool, color: Color, energy: float, saturation: float, tint_strength: float) -> void:
	_override_enabled = enabled
	_override_color = color
	_override_energy = clampf(energy, 0.0, 5.0)
	_override_saturation = clampf(saturation, -1.0, 2.0)
	_override_tint_strength = clampf(tint_strength, 0.0, 1.0)


func set_weather_runtime(global_intensity: float, stacking_enabled: bool, channels: Dictionary, current_weather: String) -> void:
	_weather_global_intensity = clampf(global_intensity, 0.0, 3.0)
	_weather_stacking_enabled = stacking_enabled
	_weather_channels = channels.duplicate(true)
	_current_weather = current_weather


func update_lighting(time_of_day: float) -> void:
	var t: float = fposmod(time_of_day, 24.0)
	var normalized_time: float = t / 24.0
	var sun_angle: float = (normalized_time - 0.25) * TAU

	# Strong but smooth daytime arc peaking in the afternoon.
	var base_sun_intensity: float = clampf(sin(sun_angle) * 2.5, 0.1, 3.0)
	var afternoon_peak: float = _window_peak(t, afternoon_start_hour, afternoon_end_hour)
	var day_factor: float = _window_peak(t, day_start_hour, day_end_hour)
	var warmth: float = clampf(1.0 - absf(t - 14.0) / 8.0, 0.3, 1.0)
	var weather_mult: float = _resolve_weather_multiplier(_current_weather)

	var sun_energy: float = afternoon_sun_energy_min + ((afternoon_sun_energy_max - afternoon_sun_energy_min) * afternoon_peak)
	sun_energy = maxf(sun_energy, base_sun_intensity * 0.72)
	if t < afternoon_start_hour or t > afternoon_end_hour:
		sun_energy = lerpf(0.2, afternoon_sun_energy_min, day_factor)
	sun_energy *= weather_mult

	var auto_light_color: Color = Color(1.0, 0.92 + warmth * 0.08, 0.85 + warmth * 0.1, 1.0)
	_override_blend = move_toward(_override_blend, 1.0 if _override_enabled else 0.0, 0.06)
	var override_color_sat: Color = _with_saturation(_override_color, _override_saturation)
	var blend_t: float = _override_blend * _override_tint_strength
	var final_light_color: Color = auto_light_color.lerp(override_color_sat, blend_t)
	var final_energy: float = lerpf(sun_energy, _override_energy, _override_blend)

	if sun_light != null:
		sun_light.light_energy = final_energy
		sun_light.light_color = final_light_color

	if sky_node != null:
		_set_if_has_property(sky_node, "sun_energy", final_energy)
		_set_if_has_property(sky_node, "tonemap_exposure", 0.95 + (0.15 * day_factor) + (0.1 * afternoon_peak))
		_set_if_has_property(sky_node, "camera_exposure", 1.0 + (0.2 * day_factor) + (0.1 * afternoon_peak))
		_set_if_has_property(sky_node, "skydome_energy", 1.0 + (0.25 * day_factor) + (0.15 * afternoon_peak))
		_set_if_has_property(sky_node, "moon_energy", lerpf(night_moon_energy_max, night_moon_energy_min, day_factor))

	if env_node != null and env_node.environment != null:
		var ambient: float = ambient_energy_night + (ambient_energy_day - ambient_energy_night) * day_factor
		ambient += 0.03 * afternoon_peak
		env_node.environment.ambient_light_energy = clampf(ambient, 0.3, 0.6)
		env_node.environment.ambient_light_color = ambient_night_color.lerp(ambient_day_color, day_factor)
		env_node.environment.ssao_enabled = true
		env_node.environment.ssao_intensity = lerpf(0.3, 0.42, day_factor)
		env_node.environment.ssao_radius = 1.2
		env_node.environment.ssao_power = 1.05

	if postfx_node != null and postfx_node.has_method("set_daylight_factor"):
		postfx_node.call("set_daylight_factor", clampf((day_factor * 0.6) + (afternoon_peak * 0.4), 0.0, 1.0))


func _resolve_weather_multiplier(current_weather: String) -> float:
	var mult: float = 1.0
	if _weather_stacking_enabled:
		var storm: float = float(_weather_channels.get("stormy", 0.0))
		var rain: float = float(_weather_channels.get("rain", 0.0))
		var fog: float = float(_weather_channels.get("foggy", 0.0))
		mult -= 0.20 * clampf(storm, 0.0, 1.0)
		mult -= 0.12 * clampf(rain, 0.0, 1.0)
		mult -= 0.14 * clampf(fog, 0.0, 1.0)
	else:
		match current_weather:
			"rain":
				mult *= 0.84
			"snow":
				mult *= 0.9
			"foggy":
				mult *= 0.78
			"stormy":
				mult *= 0.7
	return clampf(mult * maxf(_weather_global_intensity, 0.0), 0.35, 1.6)


func _with_saturation(src: Color, saturation: float) -> Color:
	var gray: float = (src.r * 0.299) + (src.g * 0.587) + (src.b * 0.114)
	var sat: float = maxf(saturation, -1.0)
	var rgb := Vector3(src.r, src.g, src.b)
	var mixed: Vector3 = Vector3(gray, gray, gray).lerp(rgb, sat)
	return Color(clampf(mixed.x, 0.0, 1.0), clampf(mixed.y, 0.0, 1.0), clampf(mixed.z, 0.0, 1.0), src.a)


func _window_peak(time_hours: float, start_hour: float, end_hour: float) -> float:
	if time_hours < start_hour or time_hours > end_hour:
		return 0.0
	var mid: float = (start_hour + end_hour) * 0.5
	var half_span: float = maxf((end_hour - start_hour) * 0.5, 0.001)
	return clampf(1.0 - (absf(time_hours - mid) / half_span), 0.0, 1.0)


func _set_if_has_property(target: Object, property_name: String, value: Variant) -> void:
	for prop in target.get_property_list():
		if String(prop.get("name", "")) == property_name:
			target.set(property_name, value)
			return
