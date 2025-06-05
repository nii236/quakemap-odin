package quakemap

get_spawn_points :: proc(quake_map: ^LoadedMap, classname: string = "") -> []SpawnPoint {
	return {}
}

get_entities_by_class :: proc(
	quake_map: ^QuakeMap,
	classname: string,
	allocator := context.allocator,
) -> []Entity {
	return {}
}

entity_has :: proc(entity: Entity, key: string) -> bool {
	return false
}

entity_get_string :: proc(entity: Entity, key: string) -> (value: string, ok: bool) {
	return
}

entity_get_int :: proc(entity: Entity, key: string) -> (value: i32, ok: bool) {
	return
}

entity_get_float :: proc(entity: Entity, key: string) -> (value: f32, ok: bool) {
	return
}

entity_get_vec3 :: proc(entity: Entity, key: string) -> (value: Vec3, ok: bool) {
	return
}
