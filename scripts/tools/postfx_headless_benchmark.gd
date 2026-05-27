extends SceneTree

const WARMUP_SECONDS: float = 1.5
const SAMPLE_SECONDS: float = 2.5

func _init() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	await process_frame
	var main_scene_res: PackedScene = load("res://scenes/main/Main.tscn") as PackedScene
	if main_scene_res == null:
		push_error("BENCH_ERROR failed_to_load_main_scene")
		quit(1)
		return
	var main_scene: Node = main_scene_res.instantiate()
	root.add_child(main_scene)
	await process_frame

	var postfx: Node = main_scene.get_node_or_null("PostProcessCanvas")
	if postfx == null:
		push_error("BENCH_ERROR missing_postfx_canvas")
		quit(1)
		return

	await _measure_mode(postfx, "Off")
	await _measure_mode(postfx, "High")
	await _measure_mode(postfx, "Medium")
	quit(0)


func _measure_mode(postfx: Node, mode_name: String) -> void:
	_apply_mode(postfx, mode_name)
	await create_timer(WARMUP_SECONDS).timeout

	var samples: Array[float] = []
	var end_time: int = Time.get_ticks_msec() + int(SAMPLE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < end_time:
		await process_frame
		samples.append(float(Performance.get_monitor(Performance.TIME_FPS)))

	if samples.is_empty():
		print("BENCH %s avg_fps=0.00 min=0.00 max=0.00 samples=0" % mode_name)
		return

	var min_fps: float = samples[0]
	var max_fps: float = samples[0]
	var sum_fps: float = 0.0
	for fps in samples:
		sum_fps += fps
		min_fps = minf(min_fps, fps)
		max_fps = maxf(max_fps, fps)
	var avg_fps: float = sum_fps / float(samples.size())
	print("BENCH %s avg_fps=%.2f min=%.2f max=%.2f samples=%d" % [mode_name, avg_fps, min_fps, max_fps, samples.size()])


func _apply_mode(postfx: Node, mode_name: String) -> void:
	match mode_name:
		"Off":
			if postfx.has_method("set_enabled"):
				postfx.call("set_enabled", false)
		"High":
			if postfx.has_method("set_enabled"):
				postfx.call("set_enabled", true)
			if postfx.has_method("set_quality_preset"):
				postfx.call("set_quality_preset", "High")
			if postfx.has_method("set_postfx_intensity"):
				postfx.call("set_postfx_intensity", 1.0)
		"Medium":
			if postfx.has_method("set_enabled"):
				postfx.call("set_enabled", true)
			if postfx.has_method("set_quality_preset"):
				postfx.call("set_quality_preset", "Medium")
			if postfx.has_method("set_postfx_intensity"):
				postfx.call("set_postfx_intensity", 1.0)
