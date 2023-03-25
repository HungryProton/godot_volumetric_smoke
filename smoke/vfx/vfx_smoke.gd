extends GPUParticles3D


func set_vfx_scale(s: float) -> void:
	draw_pass_1.size = Vector2(s, s) * 1.5
