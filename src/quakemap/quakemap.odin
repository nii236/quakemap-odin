package quakemap

loader_init :: proc(texture_path: string, allocator := context.allocator) -> MapLoader {
	return {}
}

loader_destroy :: proc(loader: ^MapLoader) {
}

load_map_from_file :: proc(loader: ^MapLoader, filepath: string) -> (LoadedMap, ParseError) {
	return {}, .None
}

load_map_from_string :: proc(loader: ^MapLoader, data: string) -> (LoadedMap, ParseError) {
	return {}, .None
}

map_destroy :: proc(quake_map: ^LoadedMap) {
}
