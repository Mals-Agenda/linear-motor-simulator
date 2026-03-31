extends MeshInstance3D

## Draws a thin cylinder between two nodes, representing a wire.
## Paths are relative to this node.

@export var from_path:   NodePath = NodePath()
@export var to_path:     NodePath = NodePath()
@export var wire_radius: float    = 0.003
@export var wire_color:  Color    = Color(0.85, 0.70, 0.10)

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	var node_a := get_node_or_null(from_path) as Node3D
	var node_b := get_node_or_null(to_path)   as Node3D
	if not node_a or not node_b:
		push_warning("Wire '%s': could not resolve from_path or to_path" % name)
		return

	var pa  := node_a.global_position
	var pb  := node_b.global_position
	var seg := pb - pa
	var len := seg.length()
	if len < 0.0001: return

	var dir := seg / len

	var cyl             := CylinderMesh.new()
	cyl.top_radius      = wire_radius
	cyl.bottom_radius   = wire_radius
	cyl.height          = len
	cyl.radial_segments = 8
	cyl.rings           = 1

	var mat             := StandardMaterial3D.new()
	mat.albedo_color    = wire_color
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.surface_set_material(0, mat)
	mesh = cyl

	var ref_up := Vector3.FORWARD if abs(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_ax   := ref_up.cross(dir).normalized()
	var z_ax   := dir.cross(x_ax).normalized()
	global_transform = Transform3D(Basis(x_ax, dir, z_ax), (pa + pb) * 0.5)
