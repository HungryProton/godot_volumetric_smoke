class_name VolumetricSmoke
extends Node3D


# This is mostly just a proof of concept that loosely attempt to emulate
# the new smoke grenade from Counter Strike 2.
# The "voxels" however are NOT aligned on a grid and rely on raycasts to avoid
# obstacles.
#
# NOTHING in there is optimized yet, this is the most simple brute force approach
# one could think of.

const VFXScene := preload("res://smoke/vfx/vfx_smoke.tscn")
const SEPARATION_MAX_CHECKS := 10
const VRC_SEPARATION_MAX := 14
const VRC_GRID_UPDATES_MAX := 6


class Voxel:
	var cell: Cell		# Parent cell currently attached to
	var pos: Vector3	# Current position
	var vel: Vector3	# Current velocity
	var time: float		# Time left to live
	var node: Node3D	# 3D node representation
	var speed_modifier: float
	var vrc_separation: int
	var vrc_grid_update: int


class Cell:
	var id: Vector3i
	var center: Vector3
	var pressure_vector: Vector3
	var weight: float
	var voxels: Array[Voxel] = []
	var neighbors: Array[Vector3i]

	func get_random() -> Array[Voxel]:
		if voxels.size() < SEPARATION_MAX_CHECKS:
			return voxels
		var start_index = randi_range(0, SEPARATION_MAX_CHECKS)
		return voxels.slice(start_index)


@export var voxel_amount := 250 # How much smoke voxels in total
@export var voxel_size := 0.8
@export var voxel_propagation_speed := 12.0 # How fast voxels separate, in m/s
@export var voxel_life_time := 40.0
@export var voxel_speed_randomness := 1.0
@export var damping := 14.0
@export var gravity := -0.25


var _voxels: Array[Voxel] = []
var _grid := {}
var _cell_size: int
var _voxel_size_squared: float
var _physic_state: PhysicsDirectSpaceState3D
var _vfx_duration: float
var _vrc_grid_pressure = 0


func _ready():
	_physic_state = get_viewport().get_world_3d().get_direct_space_state()
	_voxel_size_squared = pow(voxel_size, 2.0)
	_cell_size = ceil(voxel_size * 1.0)

	# Create every voxels with a random initial velocity
	for i in voxel_amount:
		var voxel := Voxel.new()
		voxel.speed_modifier = randf_range(1.0, 1.0 + voxel_speed_randomness)
		voxel.pos = Vector3.ZERO
		voxel.vel = _create_random_vector() * voxel.speed_modifier
		voxel.time = voxel_life_time
		voxel.node = _create_voxel_node()
		voxel.vrc_separation = randi_range(0, VRC_SEPARATION_MAX)
		voxel.vrc_grid_update = randi_range(0, VRC_GRID_UPDATES_MAX)
		_voxels.push_back(voxel)
		_update_position_in_grid(voxel, true)


func _physics_process(delta):

	_vrc_grid_pressure -= 1
	if _vrc_grid_pressure <= 0:
		_vrc_grid_pressure = randi_range(0, 2)
		_update_pressure_direction()

	# Store the expired voxels here, they'll get deleted at the end of the function
	var _voxels_delete_queue: Array[Voxel] = []

	# Update every voxels
	for voxel in _voxels:
		# Damp the velocity vector
		voxel.vel *= 1.0 - (delta * damping)

		# Apply gravity
		voxel.vel.y -= gravity * delta

		voxel.vrc_separation -= 1
		if voxel.vrc_separation <= 0:
			voxel.vrc_separation = randi_range(0, VRC_SEPARATION_MAX)

			# Accumulate the separation vector. Voxel pushes each other around.
			var separation_vector := Vector3.ZERO
			for other_voxel in voxel.cell.get_random():
				var diff = voxel.pos - other_voxel.pos
				var diff_delta = _voxel_size_squared - diff.length_squared()

				if diff_delta > 0:
					separation_vector += diff * diff_delta

			voxel.vel += separation_vector * voxel_propagation_speed * voxel.speed_modifier * delta * 2.0

		# Follow the overral movement
		voxel.vel += voxel.cell.pressure_vector * voxel_propagation_speed * delta * 0.75

		# Check if the current voxel is headed toward a collider.
		# Update its velocity if the raycast hits something.
		var ray_query := PhysicsRayQueryParameters3D.new()
		var ray_direction = voxel.vel.normalized()
		var voxel_global_position = voxel.node.global_position
		ray_query.from = voxel_global_position - (ray_direction * 0.2) # Ray starts slightly before the voxel to limit leaks
		ray_query.to = voxel_global_position + (ray_direction * voxel_size)
		var hit := _physic_state.intersect_ray(ray_query)
		if not hit.is_empty():
			voxel.vel = voxel.vel.bounce(hit.normal) * 1.10

		# Apply velocity and update position
		voxel.pos += voxel.vel * delta
		voxel.node.position = voxel.pos

		voxel.vrc_grid_update -= 1
		if voxel.vrc_grid_update <= 0:
			voxel.vrc_grid_update = randi_range(0, VRC_GRID_UPDATES_MAX)
			_update_position_in_grid(voxel)

		# Update life time
		voxel.time -= delta
		if voxel.time <= 0.0:
			_voxels_delete_queue.push_back(voxel)

	# Cleanup dead voxels
	for voxel_to_delete in _voxels_delete_queue:
		voxel_to_delete.node.stop_vfx_and_free()
		_voxels.erase(voxel_to_delete)

	# If every voxels are dead, delete this node.
	if _voxels.is_empty():
		set_physics_process(false)
		_wait_for_vfx_to_complete_and_free()


func _create_random_vector() -> Vector3:
	var v := Vector3.ZERO
	v.x = randf_range(-1.0, 1.0)
	v.y = randf_range(-1.0, 1.0)
	v.z = randf_range(-1.0, 1.0)
	return v.normalized()


func _create_voxel_node() -> Node3D:
	var vfx = VFXScene.instantiate()
	vfx.set_vfx_scale(voxel_size)
	vfx.toggle_debug_view(false)
	_vfx_duration = vfx.get_duration()
	add_child.call_deferred(vfx)
	return vfx


func _to_grid_id(v_pos: Vector3) -> Vector3i:
	var grid_id := Vector3i.ZERO
	grid_id.x = snappedi(v_pos.x, _cell_size)
	grid_id.y = snappedi(v_pos.y, _cell_size)
	grid_id.z = snappedi(v_pos.z, _cell_size)
	return grid_id


func _update_position_in_grid(voxel: Voxel, force_update := false) -> void:
	var cell_id = _to_grid_id(voxel.pos)

	if not force_update and cell_id == voxel.cell.id:
		return # Voxel is still in the same cell, nothing to do.

	# Remove the voxel from the previous cell
	if voxel.cell:
		voxel.cell.voxels.erase(voxel)
		if voxel.cell.voxels.is_empty():
			_grid.erase(voxel.cell.id)

	# Place it in the new cell
	var new_cell: Cell

	# Create the cell if it doesn't exists yet
	if not cell_id in _grid:
		new_cell = Cell.new()
		new_cell.id = cell_id
		var cell_unit = ceil(_cell_size)
		var neighbors: Array[Vector3i] = []
		new_cell.neighbors.push_back(cell_id + (Vector3i.UP * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i.DOWN * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i.LEFT * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i.RIGHT * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i.FORWARD * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i.BACK * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, 1, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, 1, -1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, 1, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, 1, -1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, 0, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, 0, -1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, 0, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, 0, -1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, -1, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(1, -1, -1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, -1, 1) * cell_unit))
		new_cell.neighbors.push_back(cell_id + (Vector3i(-1, -1, -1) * cell_unit))

		_grid[cell_id] = new_cell
	else:
		new_cell = _grid[cell_id]

	new_cell.voxels.push_back(voxel)
	voxel.cell = new_cell


func _update_pressure_direction() -> void:
	for cell_id in _grid.keys():
		var cell: Cell = _grid[cell_id]
		var sample := cell.get_random()
		if sample.is_empty():
			cell.weight = 0
			continue

		cell.center = Vector3.ZERO

		for voxel in sample:
			cell.center += voxel.pos

		cell.center /= sample.size()
		cell.weight = cell.voxels.size() / (voxel_amount * 0.3)

	for cell_id in _grid.keys():
		var cell: Cell = _grid[cell_id]

		cell.pressure_vector = Vector3.ZERO
		var neighbor_weights: float
		for neighbor_id in cell.neighbors:
			if not neighbor_id in _grid:
				continue

			var neighbor_cell: Cell = _grid[neighbor_id]
			var diff = cell.center - neighbor_cell.center
			cell.pressure_vector += diff.normalized() * neighbor_cell.weight
			neighbor_weights += neighbor_cell.weight

		var multiplier = neighbor_weights / (cell.weight + 0.1)
		cell.pressure_vector *= clamp(multiplier, -2.0, 2.0)


func _wait_for_vfx_to_complete_and_free():
	await get_tree().create_timer(_vfx_duration * 1.5).timeout
	queue_free()
