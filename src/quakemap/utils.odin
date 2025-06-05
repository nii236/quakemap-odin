package quakemap
import "core:strconv"

calculate_map_bounds :: proc(quake_map: ^QuakeMap) -> BoundingBox {
	return {}
}

parse_f32 :: proc(s: string) -> (f32, bool) {
	return strconv.parse_f32(s)
}

parse_f64 :: proc(s: string) -> (f64, bool) {
	return strconv.parse_f64(s)
}
