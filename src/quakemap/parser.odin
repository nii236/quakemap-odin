package quakemap

import "core:math"
import "core:strconv"
import "core:strings"

read :: proc(
	data: string,
	allocator := context.allocator,
) -> (
	quake_map: QuakeMap,
	err: ParseError,
) {
	lines := strings.split_lines(data, allocator)
	defer delete(lines, allocator)

	quake_map.entities = make([dynamic]Entity, allocator)

	line_idx := 0
	worldspawn_found := false

	for line_idx < len(lines) {
		line := strings.trim_space(lines[line_idx])

		if len(line) == 0 || strings.has_prefix(line, "//") {
			line_idx += 1
			continue
		}

		if line == "{" {
			line_idx += 1
			entity, read_err := read_entity(lines, &line_idx, allocator)
			if read_err != .None {
				err = read_err
				return
			}

			if entity.classname == "worldspawn" {
				quake_map.worldspawn = entity
				worldspawn_found = true
			} else {
				append(&quake_map.entities, entity)
			}
		} else {
			err = .Unexpected_Token
			return
		}

		line_idx += 1
	}

	if !worldspawn_found {
		err = .World_Spawn_Not_Found
		return
	}

	return
}

@(private)
read_entity :: proc(
	lines: []string,
	line_idx: ^int,
	allocator := context.allocator,
) -> (
	entity: Entity,
	err: ParseError,
) {
	entity.properties = make([dynamic]Property, allocator)
	entity.solids = make([dynamic]Solid, allocator)

	for line_idx^ < len(lines) {
		line := strings.trim_space(lines[line_idx^])

		if len(line) == 0 || strings.has_prefix(line, "//") {
			line_idx^ += 1
			continue
		}

		if line == "}" {
			break
		}

		if strings.has_prefix(line, "\"") {
			prop, prop_err := read_property(line)
			if prop_err != .None {
				err = prop_err
				return
			}

			if prop.key == "classname" {
				entity.classname = strings.clone(prop.value, allocator)
			} else if prop.key == "spawnflags" {
				flags, ok := strconv.parse_u64(prop.value)
				if !ok {
					err = .Expected_Float
					return
				}
				entity.spawnflags = u32(flags)
			} else {
				cloned_prop := Property {
					key   = strings.clone(prop.key, allocator),
					value = strings.clone(prop.value, allocator),
				}
				append(&entity.properties, cloned_prop)
			}
		} else if line == "{" {
			line_idx^ += 1
			solid, solid_err := read_solid(lines, line_idx, allocator)
			if solid_err != .None {
				err = solid_err
				return
			}
			append(&entity.solids, solid)
		} else {
			err = .Unexpected_Token
			return
		}

		line_idx^ += 1
	}

	return
}

@(private)
read_property :: proc(line: string) -> (prop: Property, err: ParseError) {
	if !strings.has_prefix(line, "\"") {
		err = .Unexpected_Token
		return
	}

	// Find the closing quote of the key
	key_end := -1
	for i in 1 ..< len(line) {
		if line[i] == '"' {
			key_end = i
			break
		}
	}

	if key_end == -1 {
		err = .Unexpected_EOF
		return
	}

	prop.key = line[1:key_end]

	// Skip whitespace and find the opening quote of the value
	value_start := -1
	for i in key_end + 1 ..< len(line) {
		if line[i] == '"' {
			value_start = i + 1
			break
		}
		if line[i] != ' ' && line[i] != '\t' {
			err = .Expected_Space
			return
		}
	}

	if value_start == -1 {
		err = .Unexpected_EOF
		return
	}

	// Find the closing quote of the value
	value_end := -1
	for i in value_start ..< len(line) {
		if line[i] == '"' {
			value_end = i
			break
		}
	}

	if value_end == -1 {
		err = .Unexpected_EOF
		return
	}

	prop.value = line[value_start:value_end]
	return
}

@(private)
read_solid :: proc(
	lines: []string,
	line_idx: ^int,
	allocator := context.allocator,
) -> (
	solid: Solid,
	err: ParseError,
) {
	solid.faces = make([dynamic]Face, allocator)

	for line_idx^ < len(lines) {
		line := strings.trim_space(lines[line_idx^])

		if len(line) == 0 || strings.has_prefix(line, "//") {
			line_idx^ += 1
			continue
		}

		if line == "}" {
			break
		}

		if strings.has_prefix(line, "(") {
			face, face_err := read_face(line)
			if face_err != .None {
				err = face_err
				return
			}
			append(&solid.faces, face)
		} else {
			err = .Unexpected_Token
			return
		}

		line_idx^ += 1
	}

	// Compute vertices for all faces
	compute_err := compute_vertices(&solid, allocator)
	if compute_err != .None {
		err = compute_err
		return
	}

	return
}

// Custom tokenizer that handles quoted strings
@(private)
tokenize_face_line :: proc(line: string, allocator := context.allocator) -> []string {
	tokens := make([dynamic]string, allocator)
	
	i := 0
	for i < len(line) {
		// Skip whitespace
		for i < len(line) && (line[i] == ' ' || line[i] == '\t') {
			i += 1
		}
		
		if i >= len(line) {
			break
		}
		
		// Handle quoted strings
		if line[i] == '"' {
			i += 1 // Skip opening quote
			start := i
			for i < len(line) && line[i] != '"' {
				i += 1
			}
			if i < len(line) {
				append(&tokens, line[start:i])
				i += 1 // Skip closing quote
			}
		} else {
			// Regular token
			start := i
			for i < len(line) && line[i] != ' ' && line[i] != '\t' {
				i += 1
			}
			append(&tokens, line[start:i])
		}
	}
	
	return tokens[:]
}

@(private)
read_face :: proc(line: string) -> (face: Face, err: ParseError) {
	tokens := tokenize_face_line(line, context.temp_allocator)
	defer delete(tokens, context.temp_allocator)

	if len(tokens) < 21 { 	// Minimum number of tokens expected
		err = .Unexpected_EOF
		return
	}

	// Read the three points
	token_idx := 0

	// Find first opening paren
	for token_idx < len(tokens) && tokens[token_idx] != "(" {
		token_idx += 1
	}
	if token_idx >= len(tokens) {
		err = .Expected_Open_Paren
		return
	}

	v0, v0_err := read_point(tokens[token_idx:token_idx + 5]) // ( x y z )
	if v0_err != .None {
		err = v0_err
		return
	}
	token_idx += 5

	// Find second opening paren
	for token_idx < len(tokens) && tokens[token_idx] != "(" {
		token_idx += 1
	}
	if token_idx >= len(tokens) {
		err = .Expected_Open_Paren
		return
	}

	v1, v1_err := read_point(tokens[token_idx:token_idx + 5])
	if v1_err != .None {
		err = v1_err
		return
	}
	token_idx += 5

	// Find third opening paren
	for token_idx < len(tokens) && tokens[token_idx] != "(" {
		token_idx += 1
	}
	if token_idx >= len(tokens) {
		err = .Expected_Open_Paren
		return
	}

	v2, v2_err := read_point(tokens[token_idx:token_idx + 5])
	if v2_err != .None {
		err = v2_err
		return
	}
	token_idx += 5

	// Create plane from points (flip order for counter-clockwise)
	face.plane = plane_from_points(v2, v1, v0)

	// Skip to texture name (should be next non-paren token)
	for token_idx < len(tokens) && tokens[token_idx] == ")" {
		token_idx += 1
	}

	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}

	// Read texture name
	face.texture_name = tokens[token_idx]
	token_idx += 1

	// Read texture parameters
	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}
	shift_x, shift_x_ok := strconv.parse_f64(tokens[token_idx])
	if !shift_x_ok {
		err = .Expected_Float
		return
	}
	face.shift_x = f32(shift_x)
	token_idx += 1

	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}
	shift_y, shift_y_ok := strconv.parse_f64(tokens[token_idx])
	if !shift_y_ok {
		err = .Expected_Float
		return
	}
	face.shift_y = f32(shift_y)
	token_idx += 1

	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}
	rotation, rotation_ok := strconv.parse_f64(tokens[token_idx])
	if !rotation_ok {
		err = .Expected_Float
		return
	}
	face.rotation = f32(rotation)
	token_idx += 1

	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}
	scale_x, scale_x_ok := strconv.parse_f64(tokens[token_idx])
	if !scale_x_ok {
		err = .Expected_Float
		return
	}
	face.scale_x = f32(scale_x)
	token_idx += 1

	if token_idx >= len(tokens) {
		err = .Unexpected_EOF
		return
	}
	scale_y, scale_y_ok := strconv.parse_f64(tokens[token_idx])
	if !scale_y_ok {
		err = .Expected_Float
		return
	}
	face.scale_y = f32(scale_y)

	// Set up UV axes
	uv_direction := closest_axis(face.plane.normal)
	if uv_direction.x == 1 {
		face.u_axis = {0, 1, 0}
	} else {
		face.u_axis = {1, 0, 0}
	}

	if uv_direction.z == 1 {
		face.v_axis = {0, -1, 0}
	} else {
		face.v_axis = {0, 0, -1}
	}
	
	// Apply rotation if non-zero
	if face.rotation != 0 {
		// Convert rotation to radians (negative because Quake rotates clockwise)
		angle_rad := -face.rotation * (math.PI / 180.0)
		cos_angle := f32(math.cos(f64(angle_rad)))
		sin_angle := f32(math.sin(f64(angle_rad)))
		
		// Store original axes
		original_u := face.u_axis
		original_v := face.v_axis
		
		// Rotate UV axes around the face normal
		// This performs a proper 3D rotation of the texture axes
		face.u_axis = Vec3{
			original_u.x * cos_angle - original_v.x * sin_angle,
			original_u.y * cos_angle - original_v.y * sin_angle,
			original_u.z * cos_angle - original_v.z * sin_angle,
		}
		
		face.v_axis = Vec3{
			original_u.x * sin_angle + original_v.x * cos_angle,
			original_u.y * sin_angle + original_v.y * cos_angle,
			original_u.z * sin_angle + original_v.z * cos_angle,
		}
	}

	return
}

@(private)
read_point :: proc(tokens: []string) -> (point: Vec3, err: ParseError) {
	if len(tokens) < 4 {
		err = .Unexpected_EOF
		return
	}

	if tokens[0] != "(" {
		err = .Expected_Open_Paren
		return
	}

	x, x_ok := strconv.parse_f32(tokens[1])
	if !x_ok {
		err = .Expected_Float
		return
	}

	y, y_ok := strconv.parse_f32(tokens[2])
	if !y_ok {
		err = .Expected_Float
		return
	}

	z, z_ok := strconv.parse_f32(tokens[3])
	if !z_ok {
		err = .Expected_Float
		return
	}

	point = {x, y, z}
	return
}
