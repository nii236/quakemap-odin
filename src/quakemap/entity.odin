package quakemap

import "core:strconv"
import "core:strings"

get_spawn_points :: proc(quake_map: ^LoadedMap, classname: string = "") -> []SpawnPoint {
	if classname == "" {
		return quake_map.spawn_points
	}

	filtered := make([dynamic]SpawnPoint, context.temp_allocator)
	for spawn_point in quake_map.spawn_points {
		if spawn_point.classname == classname {
			append(&filtered, spawn_point)
		}
	}
	return filtered[:]
}

get_entities_by_class :: proc(
	quake_map: ^QuakeMap,
	classname: string,
	allocator := context.allocator,
) -> []Entity {
	entities := make([dynamic]Entity, allocator)

	for entity in quake_map.entities {
		if entity.classname == classname {
			append(&entities, entity)
		}
	}

	return entities[:]
}

entity_has :: proc(entity: Entity, key: string) -> bool {
	for prop in entity.properties {
		if prop.key == key {
			return true
		}
	}
	return false
}

entity_get_string :: proc(entity: Entity, key: string) -> (value: string, ok: bool) {
	for prop in entity.properties {
		if prop.key == key {
			return prop.value, true
		}
	}
	return "", false
}

entity_get_int :: proc(entity: Entity, key: string) -> (value: i32, ok: bool) {
	str_value, has_prop := entity_get_string(entity, key)
	if !has_prop {
		return 0, false
	}

	parsed_value, parse_ok := strconv.parse_i64(str_value)
	if !parse_ok {
		return 0, false
	}

	return i32(parsed_value), true
}

entity_get_float :: proc(entity: Entity, key: string) -> (value: f32, ok: bool) {
	str_value, has_prop := entity_get_string(entity, key)
	if !has_prop {
		return 0, false
	}

	parsed_value, parse_ok := strconv.parse_f32(str_value)
	if !parse_ok {
		return 0, false
	}

	return parsed_value, true
}

entity_get_vec3 :: proc(entity: Entity, key: string) -> (value: Vec3, ok: bool) {
	str_value, has_prop := entity_get_string(entity, key)
	if !has_prop {
		return {}, false
	}

	parts := strings.split(str_value, " ", context.temp_allocator)
	defer delete(parts, context.temp_allocator)

	if len(parts) != 3 {
		return {}, false
	}

	x, x_ok := strconv.parse_f32(parts[0])
	y, y_ok := strconv.parse_f32(parts[1])
	z, z_ok := strconv.parse_f32(parts[2])

	if !x_ok || !y_ok || !z_ok {
		return {}, false
	}

	return {x, y, z}, true
}
