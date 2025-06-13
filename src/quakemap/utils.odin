package quakemap
import "core:math"
import "core:strconv"

calculate_map_bounds :: proc(quake_map: ^QuakeMap) -> BoundingBox {
	bounds := BoundingBox {
		min = {math.F32_MAX, math.F32_MAX, math.F32_MAX},
		max = {math.F32_MIN, math.F32_MIN, math.F32_MIN},
	}

	first := true

	// Check worldspawn solids
	for solid in quake_map.worldspawn.solids {
		for face in solid.faces {
			for vertex in face.vertices {
				v := vertex
				if first {
					bounds.min = v
					bounds.max = v
					first = false
				} else {
					bounds.min.x = min(bounds.min.x, v.x)
					bounds.min.y = min(bounds.min.y, v.y)
					bounds.min.z = min(bounds.min.z, v.z)
					bounds.max.x = max(bounds.max.x, v.x)
					bounds.max.y = max(bounds.max.y, v.y)
					bounds.max.z = max(bounds.max.z, v.z)
				}
			}
		}
	}

	// Check entity solids
	for entity in quake_map.entities {
		for solid in entity.solids {
			for face in solid.faces {
				for vertex in face.vertices {
					v := vertex
					if first {
						bounds.min = v
						bounds.max = v
						first = false
					} else {
						bounds.min.x = min(bounds.min.x, v.x)
						bounds.min.y = min(bounds.min.y, v.y)
						bounds.min.z = min(bounds.min.z, v.z)
						bounds.max.x = max(bounds.max.x, v.x)
						bounds.max.y = max(bounds.max.y, v.y)
						bounds.max.z = max(bounds.max.z, v.z)
					}
				}
			}
		}
	}

	// If no geometry found, return default bounds
	if first {
		bounds = BoundingBox {
			min = {-1000, -1000, -1000},
			max = {1000, 1000, 1000},
		}
	}

	return bounds
}

@(private)
parse_f32 :: proc(s: string) -> (f32, bool) {
	return strconv.parse_f32(s)
}

@(private)
parse_f64 :: proc(s: string) -> (f64, bool) {
	return strconv.parse_f64(s)
}
