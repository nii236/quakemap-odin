package quakemap

import "core:math"
import "core:math/linalg"
import "core:mem"

@(private)
plane_from_points :: proc(v0, v1, v2: Vec3) -> Plane {
	// Calculate two edge vectors
	edge1 := v1 - v0
	edge2 := v2 - v0

	// Calculate normal using cross product
	normal := linalg.normalize(linalg.cross(edge1, edge2))

	// Calculate distance from origin
	d := -linalg.dot(normal, v0)

	return Plane{normal = normal, d = d}
}

@(private)
closest_axis :: proc(v: Vec3) -> Vec3 {
	abs_v := linalg.abs(v)

	if abs_v.x >= abs_v.y && abs_v.x >= abs_v.z {
		return {1, 0, 0} // X axis
	}
	if abs_v.y >= abs_v.z {
		return {0, 1, 0} // Y axis
	}
	return {0, 0, 1} // Z axis
}

@(private)
compute_vertices :: proc(solid: ^Solid, allocator := context.allocator) -> ParseError {
	vertices := make([dynamic]Vec3, allocator)
	clipped := make([dynamic]Vec3, allocator)
	defer delete(vertices)
	defer delete(clipped)

	for &face, i in solid.faces {
		// Create a large quad for this face
		quad := make_quad(face.plane, 1000000.0)
		clear(&vertices)
		append(&vertices, ..quad[:])

		// Clip against all other faces
		for &clip_face, j in solid.faces {
			if i == j do continue

			clear(&clipped)
			clip(vertices[:], clip_face.plane, &clipped)

			if len(clipped) < 3 {
				return .Degenerate_Face
			}

			// Swap vertices and clipped
			vertices, clipped = clipped, vertices
		}

		// Store the final vertices for this face
		face.vertices = make([]Vec3, len(vertices), allocator)
		copy(face.vertices, vertices[:])

		// Round vertices to nearest integer to fix cracks
		for &vertex in face.vertices {
			vertex.x = math.round(vertex.x)
			vertex.y = math.round(vertex.y)
			vertex.z = math.round(vertex.z)
		}
	}

	return .None
}

@(private)
make_quad :: proc(plane: Plane, radius: f32) -> [4]Vec3 {
	direction := closest_axis(plane.normal)
	up := direction.z == 1 ? Vec3{1, 0, 0} : Vec3{0, 0, -1}

	// Make up perpendicular to the plane normal
	upv := linalg.dot(up, plane.normal)
	up = linalg.normalize(up - plane.normal * upv)
	right := linalg.cross(up, plane.normal)

	up *= radius
	right *= radius

	origin := plane.normal * -plane.d

	return {origin - right - up, origin + right - up, origin + right + up, origin - right + up}
}

@(private)
clip :: proc(vertices: []Vec3, clip_plane: Plane, result: ^[dynamic]Vec3) {
	epsilon :: 0.0001

	if len(vertices) == 0 do return

	distances := make([]f32, len(vertices), context.temp_allocator)
	defer delete(distances, context.temp_allocator)

	cb, cf := 0, 0

	// Calculate distances and count vertices behind/in front
	for vertex, i in vertices {
		distance := linalg.dot(clip_plane.normal, vertex) + clip_plane.d
		if distance < -epsilon {
			cb += 1
		} else if distance > epsilon {
			cf += 1
		} else {
			distance = 0
		}
		distances[i] = distance
	}

	// Handle special cases
	if cb == 0 && cf == 0 {
		// Co-planar
		return
	} else if cb == 0 {
		// All vertices in front
		return
	} else if cf == 0 {
		// All vertices behind - keep all
		append(result, ..vertices)
		return
	}

	// Clip the polygon
	for i in 0 ..< len(vertices) {
		j := (i + 1) % len(vertices)

		s := vertices[i]
		e := vertices[j]
		sd := distances[i]
		ed := distances[j]

		// Keep vertex if behind the plane
		if sd <= 0 {
			append(result, s)
		}

		// Add intersection if crossing the plane
		if (sd < 0 && ed > 0) || (ed < 0 && sd > 0) {
			t := sd / (sd - ed)
			intersect := linalg.lerp(s, e, t)

			// Snap to plane if normal is axis-aligned
			if clip_plane.normal.x == 1 do intersect.x = -clip_plane.d
			if clip_plane.normal.x == -1 do intersect.x = clip_plane.d
			if clip_plane.normal.y == 1 do intersect.y = -clip_plane.d
			if clip_plane.normal.y == -1 do intersect.y = clip_plane.d
			if clip_plane.normal.z == 1 do intersect.z = -clip_plane.d
			if clip_plane.normal.z == -1 do intersect.z = clip_plane.d

			append(result, intersect)
		}
	}
}
