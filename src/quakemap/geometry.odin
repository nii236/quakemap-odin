package quakemap


plane_from_points :: proc(v0, v1, v2: Vec3d) -> Plane {
	return {}
}

closest_axis :: proc(v: Vec3d) -> Vec3d {
	return {}
}

compute_vertices :: proc(solid: ^Solid, allocator := context.allocator) -> ParseError {
	return .None
}

make_quad :: proc(plane: Plane, radius: f32) -> [4]Vec3d {
	return {}
}

clip :: proc(vertices: []Vec3d, plane: Plane, result: ^[dynamic]Vec3d) {
}
