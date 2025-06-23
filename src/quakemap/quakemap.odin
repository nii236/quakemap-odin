package quakemap

import "core:os"
import "core:strconv"
import "core:strings"

loader_init :: proc(texture_path: string, allocator := context.allocator) -> MapLoader {
	return MapLoader {
		allocator = allocator,
		materials = make(map[string]MaterialInfo, allocator),
		texture_path = texture_path,
		fallback_material = MaterialInfo{handle = nil, width = 32, height = 32},
	}
}

loader_destroy :: proc(loader: ^MapLoader) {
	delete(loader.materials)
}

load_map_from_file :: proc(loader: ^MapLoader, filepath: string) -> (LoadedMap, ParseError) {
	data, ok := os.read_entire_file(filepath, loader.allocator)
	if !ok {
		return {}, .File_Not_Found
	}
	defer delete(data, loader.allocator)

	return load_map_from_string(loader, string(data))
}

load_map_from_string :: proc(loader: ^MapLoader, data: string) -> (LoadedMap, ParseError) {
	// Parse the map data
	quake_map, parse_err := read(data, loader.allocator)
	if parse_err != .None {
		return {}, parse_err
	}

	// Build collision data
	collision_data := build_collision_data(&quake_map, loader.allocator)

	// Calculate map bounds
	map_bounds := calculate_map_bounds(&quake_map)

	// Extract spawn points
	spawn_points := extract_spawn_points(&quake_map, loader.allocator)

	// Build meshes
	world_geometry := build_world_meshes(&quake_map, &loader.materials, loader.allocator)
	entity_geometry := build_entity_meshes(&quake_map, &loader.materials, loader.allocator)

	loaded_map := LoadedMap {
		world_geometry  = world_geometry,
		entity_geometry = entity_geometry,
		spawn_points    = spawn_points,
		map_bounds      = map_bounds,
		collision_data  = collision_data,
	}

	return loaded_map, .None
}

quake_map_destroy :: proc(quake_map: ^QuakeMap) {
	// Clean up worldspawn entity
	destroy_entity(&quake_map.worldspawn)

	// Clean up all other entities
	for &entity in quake_map.entities {
		destroy_entity(&entity)
	}
	delete(quake_map.entities)
}

@(private)
destroy_entity :: proc(entity: ^Entity) {
	// Free classname string
	delete(entity.classname)

	// Free all property key-value pairs
	for prop in entity.properties {
		delete(prop.key)
		delete(prop.value)
	}
	delete(entity.properties)

	// Free all solids
	for &solid in entity.solids {
		for &face in solid.faces {
			delete(face.vertices)
		}
		delete(solid.faces)
	}
	delete(entity.solids)
}

map_destroy :: proc(quake_map: ^LoadedMap) {
	// Clean up meshes
	for mesh in quake_map.world_geometry {
		delete(mesh.vertices)
		delete(mesh.indices)
	}
	delete(quake_map.world_geometry)

	for mesh in quake_map.entity_geometry {
		delete(mesh.vertices)
		delete(mesh.indices)
	}
	delete(quake_map.entity_geometry)

	// Clean up spawn points
	for spawn_point in quake_map.spawn_points {
		delete(spawn_point.properties)
	}
	delete(quake_map.spawn_points)

	// Clean up collision data
	for solid in quake_map.collision_data.solids {
		for face in solid.faces {
			delete(face.vertices)
		}
		delete(solid.faces)
	}
	delete(quake_map.collision_data.solids)
	delete(quake_map.collision_data.spatial_grid.cells)
}

@(private)
extract_spawn_points :: proc(
	quake_map: ^QuakeMap,
	allocator := context.allocator,
) -> []SpawnPoint {
	spawn_points := make([dynamic]SpawnPoint, allocator)

	for entity in quake_map.entities {
		if strings.contains(entity.classname, "info_player") ||
		   strings.contains(entity.classname, "spawn") {

			spawn_point := SpawnPoint {
				classname  = entity.classname,
				properties = make(map[string]string, allocator),
			}

			// Copy properties
			for prop in entity.properties {
				spawn_point.properties[prop.key] = prop.value
			}

			// Try to get position from "origin" property
			if origin_str, has_origin := spawn_point.properties["origin"]; has_origin {
				if origin, ok := parse_vec3_from_string(origin_str); ok {
					spawn_point.position = origin
				}
			}

			// Try to get rotation from "angle" or "angles" property
			if angle_str, has_angle := spawn_point.properties["angle"]; has_angle {
				if angle, ok := parse_f32(angle_str); ok {
					spawn_point.rotation = {0, angle, 0}
				}
			} else if angles_str, has_angles := spawn_point.properties["angles"]; has_angles {
				if angles, ok := parse_vec3_from_string(angles_str); ok {
					spawn_point.rotation = angles
				}
			}

			append(&spawn_points, spawn_point)
		}
	}

	return spawn_points[:]
}

@(private)
parse_vec3_from_string :: proc(s: string) -> (Vec3, bool) {
	parts := strings.split(s, " ", context.temp_allocator)
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
