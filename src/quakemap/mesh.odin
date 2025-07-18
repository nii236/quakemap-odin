package quakemap

import "core:math/linalg"
import "core:strings"

@(private)
build_world_meshes :: proc(
	quake_map: ^QuakeMap,
	materials: ^map[string]MaterialInfo,
	allocator := context.allocator,
) -> []Mesh {
	return build_meshes_for_entity(&quake_map.worldspawn, materials, allocator)
}

@(private)
build_entity_meshes :: proc(
	quake_map: ^QuakeMap,
	materials: ^map[string]MaterialInfo,
	allocator := context.allocator,
) -> []Mesh {
	all_meshes := make([dynamic]Mesh, allocator)

	for &entity in quake_map.entities {
		entity_meshes := build_meshes_for_entity(&entity, materials, allocator)
		append(&all_meshes, ..entity_meshes)
		delete(entity_meshes, allocator)
	}

	return all_meshes[:]
}

@(private)
build_meshes_for_entity :: proc(
	entity: ^Entity,
	materials: ^map[string]MaterialInfo,
	allocator := context.allocator,
) -> []Mesh {
	// Group faces by material
	texture_face_mapping := make(map[string][dynamic]Face, allocator)
	defer {
		for _, faces in texture_face_mapping {
			delete(faces)
		}
		delete(texture_face_mapping)
	}

	for solid in entity.solids {
		for face in solid.faces {
			if face.texture_name not_in texture_face_mapping {
				texture_face_mapping[face.texture_name] = make([dynamic]Face, allocator)
			}
			append(&texture_face_mapping[face.texture_name], face)
		}
	}

	// Build a mesh for each material
	meshes := make([dynamic]Mesh, allocator)

	for material_name, faces in texture_face_mapping {
		if len(faces) == 0 do continue
		
		// Handle special case for map editor placeholder material
		actual_material_name := material_name
		if material_name == "__TB_empty" {
			actual_material_name = "checkboard"
		}
		
		material, exists := materials[actual_material_name]
		if !exists {
			// Create a basic material if none exists
			material = MaterialInfo{
				name = actual_material_name,
				width = 64,  // Default texture size
				height = 64,
			}
		}
		// Ensure the material name is always set - create a copy so we can modify it
		material_copy := material
		material_copy.name = strings.clone(actual_material_name, allocator)
		mesh := build_mesh_from_faces(faces[:], material_copy, allocator)
		append(&meshes, mesh)
	}

	return meshes[:]
}

@(private)
build_mesh_from_faces :: proc(
	faces: []Face,
	material: MaterialInfo,
	allocator := context.allocator,
) -> Mesh {
	vertices := make([dynamic]Vertex, allocator)
	indices := make([dynamic]u32, allocator)

	for face in faces {
		if len(face.vertices) < 3 do continue

		// Calculate face normal
		normal := Vec3 {
			f32(face.plane.normal.x),
			f32(face.plane.normal.y),
			f32(face.plane.normal.z),
		}

		// Get material info for UV scaling
		tex_scale := Vec3{1.0 / f32(material.width), 1.0 / f32(material.height), 1.0}

		// Calculate UV coordinates for each vertex
		face_vertices := make([]Vertex, len(face.vertices), context.temp_allocator)
		defer delete(face_vertices, context.temp_allocator)

		for vertex, i in face.vertices {
			pos := vertex

			// Calculate UV using face texture parameters
			u := linalg.dot(face.u_axis, vertex) / face.scale_x + face.shift_x
			v := linalg.dot(face.v_axis, vertex) / face.scale_y + face.shift_y

			uv := [2]f32{u * tex_scale.x, v * tex_scale.y}

			face_vertices[i] = Vertex {
				position = pos,
				normal   = normal,
				uv       = uv,
				color    = {1, 1, 1, 1}, // Default white
			}
		}

		// Triangulate the face (fan triangulation)
		start_index := u32(len(vertices))
		append(&vertices, ..face_vertices)

		for i in 1 ..< len(face_vertices) - 1 {
			append(&indices, start_index)
			append(&indices, start_index + u32(i))
			append(&indices, start_index + u32(i + 1))
		}
	}

	// Calculate mesh bounds
	bounds := calculate_mesh_bounds(vertices[:])
	return Mesh{vertices = vertices[:], indices = indices[:], material = material, bounds = bounds}
}

@(private)
calculate_mesh_bounds :: proc(vertices: []Vertex) -> BoundingBox {
	if len(vertices) == 0 {
		return {}
	}

	bounds := BoundingBox {
		min = vertices[0].position,
		max = vertices[0].position,
	}

	for vertex in vertices[1:] {
		bounds.min.x = min(bounds.min.x, vertex.position.x)
		bounds.min.y = min(bounds.min.y, vertex.position.y)
		bounds.min.z = min(bounds.min.z, vertex.position.z)
		bounds.max.x = max(bounds.max.x, vertex.position.x)
		bounds.max.y = max(bounds.max.y, vertex.position.y)
		bounds.max.z = max(bounds.max.z, vertex.position.z)
	}

	return bounds
}
