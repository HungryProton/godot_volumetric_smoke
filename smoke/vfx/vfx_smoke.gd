extends GPUParticles3D


func get_duration() -> float:
	return lifetime


func set_vfx_scale(s: float) -> void:
	draw_pass_1.size = Vector2(s, s) * 1.5


func stop_vfx_and_free() -> void:
	emitting = false
	await get_tree().create_timer(lifetime).timeout

	queue_free()
