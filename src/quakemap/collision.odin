package quakemap


check_collision :: proc(collision_data: ^CollisionData, position: Vec3, size: Vec3) -> bool {
	return false
}

find_floor_height :: proc(
	collision_data: ^CollisionData,
	x, z: f32,
) -> (
	height: f32,
	found: bool,
) {
	return 0, false
}
@(private)
build_collision_data :: proc(
	quake_map: ^QuakeMap,
	allocator := context.allocator,
) -> CollisionData {
	return {}
}
