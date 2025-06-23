package quakemap

import "core:math"
import "core:math/linalg"

check_collision :: proc(collision_data: ^CollisionData, position: Vec3, size: Vec3) -> bool {
	half_size := size * 0.5
	test_bounds := BoundingBox {
		min = position - half_size,
		max = position + half_size,
	}

	for solid in collision_data.solids {
		if check_bounds_overlap(test_bounds, solid.bounds) {
			if check_point_in_solid(solid, position) {
				return true
			}
		}
	}

	return false
}

find_floor_height :: proc(
	collision_data: ^CollisionData,
	x, z: f32,
) -> (
	height: f32,
	found: bool,
) {
	highest_floor := f32(-math.F32_MAX)
	found_floor := false

	for solid in collision_data.solids {
		// Check if this solid could contain our X,Z position
		if x >= solid.bounds.min.x &&
		   x <= solid.bounds.max.x &&
		   z >= solid.bounds.min.z &&
		   z <= solid.bounds.max.z {

			for face in solid.faces {
				// Check if this is a horizontal face (floor/ceiling)
				if abs(face.plane.normal.y) > 0.7 && face.plane.normal.y > 0 { 	// Floor
					// Calculate height at this X,Z position
					if face.plane.normal.y != 0 {
						face_height :=
							(-face.plane.d - face.plane.normal.x * x - face.plane.normal.z * z) /
							face.plane.normal.y

						// Check if this point is within the face bounds
						if point_in_face_bounds(Vec3{x, face_height, z}, face) {
							if face_height > highest_floor {
								highest_floor = face_height
								found_floor = true
							}
						}
					}
				}
			}
		}
	}

	return highest_floor, found_floor
}

@(private)
build_collision_data :: proc(
	quake_map: ^QuakeMap,
	allocator := context.allocator,
) -> CollisionData {
	collision_data := CollisionData {
		solids = make([dynamic]CollisionSolid, allocator),
	}

	// Convert worldspawn solids
	for solid in quake_map.worldspawn.solids {
		collision_solid := convert_to_collision_solid(solid, allocator)
		append(&collision_data.solids, collision_solid)
	}

	// Convert entity solids
	for entity in quake_map.entities {
		for solid in entity.solids {
			collision_solid := convert_to_collision_solid(solid, allocator)
			append(&collision_data.solids, collision_solid)
		}
	}

	return collision_data
}

@(private)
convert_to_collision_solid :: proc(
	solid: Solid,
	allocator := context.allocator,
) -> CollisionSolid {
	collision_solid := CollisionSolid {
		faces = make([dynamic]CollisionFace, allocator),
	}

	// Convert faces
	for face in solid.faces {
		collision_face := CollisionFace {
			plane    = face.plane,
			vertices = make([]Vec3, len(face.vertices), allocator),
		}

		copy(collision_face.vertices, face.vertices)

		collision_face.bounds = calculate_face_bounds(collision_face.vertices)

		append(&collision_solid.faces, collision_face)
	}

	collision_solid.bounds = calculate_solid_bounds(collision_solid.faces[:])

	return collision_solid
}

@(private)
calculate_face_bounds :: proc(vertices: []Vec3) -> BoundingBox {
	if len(vertices) == 0 {
		return {}
	}

	bounds := BoundingBox {
		min = vertices[0],
		max = vertices[0],
	}

	for vertex in vertices[1:] {
		bounds.min.x = min(bounds.min.x, vertex.x)
		bounds.min.y = min(bounds.min.y, vertex.y)
		bounds.min.z = min(bounds.min.z, vertex.z)
		bounds.max.x = max(bounds.max.x, vertex.x)
		bounds.max.y = max(bounds.max.y, vertex.y)
		bounds.max.z = max(bounds.max.z, vertex.z)
	}

	return bounds
}

@(private)
calculate_solid_bounds :: proc(faces: []CollisionFace) -> BoundingBox {
	if len(faces) == 0 {
		return {}
	}

	bounds := faces[0].bounds

	for face in faces[1:] {
		bounds.min.x = min(bounds.min.x, face.bounds.min.x)
		bounds.min.y = min(bounds.min.y, face.bounds.min.y)
		bounds.min.z = min(bounds.min.z, face.bounds.min.z)
		bounds.max.x = max(bounds.max.x, face.bounds.max.x)
		bounds.max.y = max(bounds.max.y, face.bounds.max.y)
		bounds.max.z = max(bounds.max.z, face.bounds.max.z)
	}

	return bounds
}

@(private)
check_bounds_overlap :: proc(a, b: BoundingBox) -> bool {
	return(
		a.max.x >= b.min.x &&
		a.min.x <= b.max.x &&
		a.max.y >= b.min.y &&
		a.min.y <= b.max.y &&
		a.max.z >= b.min.z &&
		a.min.z <= b.max.z \
	)
}

@(private)
check_point_in_solid :: proc(solid: CollisionSolid, point: Vec3) -> bool {
	// Point is inside solid if it's behind all planes
	for face in solid.faces {
		distance := linalg.dot(face.plane.normal, point) + face.plane.d
		if distance > 0.001 { 	// Point is in front of this plane
			return false
		}
	}
	return true
}

@(private)
point_in_face_bounds :: proc(point: Vec3, face: CollisionFace) -> bool {
	return(
		point.x >= face.bounds.min.x &&
		point.x <= face.bounds.max.x &&
		point.y >= face.bounds.min.y &&
		point.y <= face.bounds.max.y &&
		point.z >= face.bounds.min.z &&
		point.z <= face.bounds.max.z \
	)
}
