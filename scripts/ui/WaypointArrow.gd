extends Control
class_name WaypointArrow
## WaypointArrow — the one thing a free-roaming game owes a player who does not
## yet know the map: a direction.
##
## Draws a chevron pointing from the screen's top-centre toward the current
## objective, in screen space, from the same world-space delta the camera uses.
## It is deliberately small and never labels anything: the objective line above
## it says WHAT, the arrow says WHERE.
##
## Playtest 6: "no story telling, user not understand what to do". A player who
## has to guess which of four directions the stones are in does not read that as
## exploration, they read it as being lost.

const SIZE := 7.0

var _dir := Vector2.ZERO
var _on := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE * 2, SIZE * 2)


## `delta_world` is target minus player, in world pixels (y down).
func point_at(delta_world: Vector2) -> void:
	var on := delta_world.length() > 24.0
	if on != _on:
		_on = on
		queue_redraw()
	if not on:
		return
	var d := delta_world.normalized()
	if d.distance_to(_dir) > 0.01:
		_dir = d
		queue_redraw()


func hide_arrow() -> void:
	if _on:
		_on = false
		queue_redraw()


func _draw() -> void:
	if not _on:
		return
	var c := size * 0.5
	# A chevron built from the direction vector, so it points exactly at the
	# target rather than at one of eight compass points.
	var fwd := _dir
	var side := Vector2(-fwd.y, fwd.x)
	var tip := c + fwd * SIZE
	var left := c - fwd * SIZE * 0.6 + side * SIZE * 0.8
	var right := c - fwd * SIZE * 0.6 - side * SIZE * 0.8
	var inner := c - fwd * SIZE * 0.15
	var pts := PackedVector2Array()
	pts.append(tip)
	pts.append(left)
	pts.append(inner)
	pts.append(right)
	draw_colored_polygon(pts, Color(0.97, 0.87, 0.65, 0.92))
