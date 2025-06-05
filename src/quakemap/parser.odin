package quakemap


read :: proc(
	data: string,
	allocator := context.allocator,
) -> (
	quake_map: QuakeMap,
	err: ParseError,
) {
	return
}

read_entity :: proc(
	lines: []string,
	line_idx: ^int,
	allocator := context.allocator,
) -> (
	entity: Entity,
	err: ParseError,
) {
	return
}

read_property :: proc(line: string) -> (prop: Property, err: ParseError) {
	return
}

read_solid :: proc(
	lines: []string,
	line_idx: ^int,
	allocator := context.allocator,
) -> (
	solid: Solid,
	err: ParseError,
) {
	return
}

read_face :: proc(line: string) -> (face: Face, err: ParseError) {
	return
}

read_point :: proc(tokens: []string) -> (point: Vec3d, err: ParseError) {
	return
}
