extends GPUParticles3D


func toggle_debug_view(enabled) -> void:
	%DebugCube.visible = enabled
	emitting = not enabled


func get_duration() -> float:
	return lifetime


func set_vfx_scale(s: float) -> void:
	draw_pass_1.size = Vector2(s, s) * 1.25
	%DebugCube.mesh.size = Vector3(s, s, s)


func stop_vfx_and_free() -> void:
	emitting = false
	await get_tree().create_timer(lifetime).timeout

	queue_free()


func _unhandled_input(_event):
	if Input.is_action_just_released("toggle_debug"):
		toggle_debug_view(not %DebugCube.visible)
