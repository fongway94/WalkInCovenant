extends RefCounted
class_name PaintedBackdrop
## Draw a single image as a cover, keeping its proportions at 16:9, 4:3 or a
## wider phone aspect. This runs only from the owning Control's draw callback.

static func draw_cover(canvas: CanvasItem, texture: Texture2D, size: Vector2) -> void:
	if canvas == null or texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var image_size := texture.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return
	var factor := maxf(size.x / image_size.x, size.y / image_size.y)
	var visible := size / factor
	var source := Rect2((image_size - visible) * 0.5, visible)
	canvas.draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), source)
