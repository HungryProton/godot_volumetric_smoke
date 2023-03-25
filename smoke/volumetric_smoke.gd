class_name VolumetricSmoke
extends Node3D


# This is mostly just a proof of concept that loosely attempt to emulate
# the new smoke grenade from Counter Strike 2.
# The "voxels" however are NOT aligned on a grid and rely on raycasts to avoid
# obstacles.
#
# NOTHING in there is optimized yet, this is the most simple brute force approach
# one could think of.


class Voxel:
	var pos: Vector3
	var vel: Vector3
	var time: float
	var node: Node3D


@export var voxel_amount := 100 # How much smoke voxels in total
@export var voxel_size := 0.75
@export var voxel_propagation_speed := 8.0 # How fast voxels separate, in m/s
@export var voxel_life_time := 5.0
@export var voxel_speed_randomness := 1.0
@export var damping := 8.0
@export var gravity := -0.25


var _voxels: Array[Voxel] = []
var _voxel_size_squared: float
var _physic_state: PhysicsDirectSpaceState3D


func _ready():
	_physic_state = get_viewport().get_world_3d().get_direct_space_state()
	_voxel_size_squared = pow(voxel_size, 2.0)

	# Create every voxels with a random initial velocity
	for i in voxel_amount:
		var voxel := Voxel.new()
		voxel.pos = Vector3.ZERO
		voxel.vel = _create_random_vector()
		voxel.time = 5.0
		voxel.node = _create_voxel_node()
		_voxels.push_back(voxel)


func _physics_process(delta):

	# Store the expired voxels here, they'll get deleted at the end of the function
	var _voxels_delete_queue: Array[Voxel] = []

	# Update every voxels
	for voxel in _voxels:

		# Accumulate the separation vector. Voxel pushes each other around.
		var separation_vector := Vector3.ZERO
		for other_voxel in _voxels:
			var dist_squared = voxel.pos.distance_squared_to(other_voxel.pos)
			if dist_squared < _voxel_size_squared:
				separation_vector += (voxel.pos - other_voxel.pos)

		voxel.vel += separation_vector * voxel_propagation_speed * delta * 0.75

		# Check if the current voxel is headed toward a collider.
		# Update its velocity if the raycast hits something.
		var ray_query := PhysicsRayQueryParameters3D.new()
		ray_query.from = voxel.node.global_position
		ray_query.to = ray_query.from + (voxel.vel.normalized() * voxel_size)
		var hit := _physic_state.intersect_ray(ray_query)
		if not hit.is_empty():
			voxel.vel = voxel.vel.bounce(hit.normal) * 0.75

		# Apply gravity
		voxel.vel.y -= gravity * delta

		# Damp the velocity vector
		voxel.vel *= 1.0 - (delta * damping)

		# Apply velocity and update position
		voxel.pos += voxel.vel * delta
		voxel.node.position = voxel.pos

		# Update life time
		voxel.time -= delta
		if voxel.time <= 0.0:
			pass


func _create_random_vector() -> Vector3:
	var v := Vector3.ZERO
	v.x = randf_range(-1.0, 1.0)
	v.y = randf_range(-1.0, 1.0) * 0.2
	v.z = randf_range(-1.0, 1.0)
	v = v.normalized()
	v *= randf_range(1.0, 1.0 + voxel_speed_randomness)# * voxel_propagation_speed
	return v


func _create_voxel_node() -> Node3D:
	var vfx = preload("res://smoke/vfx/vfx_smoke.tscn").instantiate()
	vfx.set_vfx_scale(voxel_size)
	add_child(vfx)
	return vfx
