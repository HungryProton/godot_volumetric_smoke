extends Node3D


var _physic_state: PhysicsDirectSpaceState3D
var _camera: Camera3D


func _ready() -> void:
	_physic_state = get_viewport().get_world_3d().get_direct_space_state()
	_camera = get_viewport().get_camera_3d()


func _physics_process(_delta):
	if Input.is_action_just_released("spawn_smoke"):
		# Mouse position to world coordinates
		var ray_query := PhysicsRayQueryParameters3D.new()
		var mouse_pos = get_viewport().get_mouse_position()
		ray_query.from = _camera.project_ray_origin(mouse_pos)
		ray_query.to = ray_query.from + _camera.project_ray_normal(mouse_pos) * 100.0
		var hit := _physic_state.intersect_ray(ray_query)

		if hit.is_empty():
			return

		# Spawn a smoke cloud where the user clicked
		var smoke = VolumetricSmoke.new()
		smoke.position = hit.position
		add_child(smoke)
