package quakemap

build_world_meshes :: proc(
	quake_map: ^QuakeMap,
	materials: ^map[string]MaterialInfo,
	allocator := context.allocator,
) -> []Mesh {
	return {}
}

build_entity_meshes :: proc(
	quake_map: ^QuakeMap,
	materials: ^map[string]MaterialInfo,
	allocator := context.allocator,
) -> []Mesh {
	return {}
}
