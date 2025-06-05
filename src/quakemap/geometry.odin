package quakemap


@(private)
plane_from_points :: proc(v0, v1, v2: Vec3d) -> Plane {
	return {}
}

@(private)
closest_axis :: proc(v: Vec3d) -> Vec3d {
	return {}
}

@(private)
compute_vertices :: proc(solid: ^Solid, allocator := context.allocator) -> ParseError {
	return .None
}

@(private)
make_quad :: proc(plane: Plane, radius: f32) -> [4]Vec3d {
	return {}
}

@(private)
clip :: proc(vertices: []Vec3d, plane: Plane, result: ^[dynamic]Vec3d) {
}
