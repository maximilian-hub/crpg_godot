@tool
extends TileMapLayer
class_name OverworldCollisionGrid

const GRID_SIZE := Vector2i(10, 10)
const CELL_SIZE := 16
const FULL_BLOCK_SOURCE_ID := 0
const EDGE_SOURCE_ID := 1

enum Edge {
	NONE = 0,
	NORTH = 1,
	EAST = 2,
	SOUTH = 4,
	WEST = 8,
	ALL = NORTH | EAST | SOUTH | WEST,
}

const EDGE_DIRECTIONS := {
	Edge.NORTH: Vector2i.UP,
	Edge.EAST: Vector2i.RIGHT,
	Edge.SOUTH: Vector2i.DOWN,
	Edge.WEST: Vector2i.LEFT,
}

@export var show_collision_overlay_in_game: bool = false

func _ready() -> void:
	collision_enabled = true
	# TileMapLayer deactivates its physics quadrants when hidden. Keep the layer
	# active and make only its debug artwork transparent at runtime.
	visible = true
	modulate.a = 1.0 if Engine.is_editor_hint() or show_collision_overlay_in_game else 0.0
	rebuild_edge_collision_geometry()

func is_cell_blocked(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return true
	return get_cell_source_id(cell) == FULL_BLOCK_SOURCE_ID

func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y

## Returns the persistent map-space edge flags authored on this cell.
## Edge atlas coordinates encode the mask as x + y * 4.
## Prefer painting the edge on the cell containing the related artwork. Either
## neighbor may declare a shared boundary; duplicate declarations are harmless
## because queries merge them and generated geometry canonicalizes them.
func get_edge_mask(cell: Vector2i) -> int:
	if get_cell_source_id(cell) != EDGE_SOURCE_ID:
		return Edge.NONE
	var atlas_coords := get_cell_atlas_coords(cell)
	var mask := atlas_coords.x + atlas_coords.y * 4
	return mask if mask >= Edge.NONE and mask <= Edge.ALL else Edge.NONE

func atlas_coords_for_edge_mask(mask: int) -> Vector2i:
	var safe_mask := clampi(mask, Edge.NONE, Edge.ALL)
	return Vector2i(safe_mask % 4, safe_mask / 4)

## Tests the shared physical boundary between two adjacent cells. A boundary is
## blocked if either neighboring cell authors its corresponding edge. This makes
## an edge two-sided in map space rather than a direction-specific movement rule.
func is_boundary_blocked(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var direction := to_cell - from_cell
	if abs(direction.x) + abs(direction.y) != 1:
		return true
	if is_cell_blocked(from_cell) or is_cell_blocked(to_cell):
		return true
	var from_edge := edge_for_direction(direction)
	var to_edge := edge_for_direction(-direction)
	return (
		(get_edge_mask(from_cell) & from_edge) != 0
		or (get_edge_mask(to_cell) & to_edge) != 0
	)

func edge_for_direction(direction: Vector2i) -> int:
	match direction:
		Vector2i.UP: return Edge.NORTH
		Vector2i.RIGHT: return Edge.EAST
		Vector2i.DOWN: return Edge.SOUTH
		Vector2i.LEFT: return Edge.WEST
		_: return Edge.NONE

## Builds two-sided SegmentShape2D barriers from the same edge-mask tile data
## used by grid movement. Shared boundaries are canonicalized and emitted once.
## This geometry can also serve future continuous movement without redefining
## collision as directional tile-entry rules.
func rebuild_edge_collision_geometry() -> void:
	var previous := get_node_or_null("GeneratedEdgeBarriers")
	if previous != null:
		previous.free()

	var body := StaticBody2D.new()
	body.name = "GeneratedEdgeBarriers"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var boundaries: Dictionary = {}
	for cell in get_used_cells():
		var mask := get_edge_mask(cell)
		for edge in EDGE_DIRECTIONS:
			if (mask & edge) == 0:
				continue
			var boundary := _boundary_segment(cell, edge)
			boundaries[boundary.key] = boundary

	for boundary in boundaries.values():
		var shape := SegmentShape2D.new()
		shape.a = boundary.start
		shape.b = boundary.end
		var collision_shape := CollisionShape2D.new()
		collision_shape.shape = shape
		body.add_child(collision_shape)

func _boundary_segment(cell: Vector2i, edge: int) -> Dictionary:
	var origin := Vector2(cell * CELL_SIZE)
	match edge:
		Edge.NORTH:
			return {"key": Vector3i(cell.x, cell.y, 0), "start": origin, "end": origin + Vector2(CELL_SIZE, 0)}
		Edge.EAST:
			return {"key": Vector3i(cell.x + 1, cell.y, 1), "start": origin + Vector2(CELL_SIZE, 0), "end": origin + Vector2(CELL_SIZE, CELL_SIZE)}
		Edge.SOUTH:
			return {"key": Vector3i(cell.x, cell.y + 1, 0), "start": origin + Vector2(0, CELL_SIZE), "end": origin + Vector2(CELL_SIZE, CELL_SIZE)}
		Edge.WEST:
			return {"key": Vector3i(cell.x, cell.y, 1), "start": origin, "end": origin + Vector2(0, CELL_SIZE)}
		_:
			return {"key": Vector3i.ZERO, "start": origin, "end": origin}
