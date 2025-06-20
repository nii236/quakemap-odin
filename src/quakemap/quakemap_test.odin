package quakemap

import "core:math/linalg"
import "core:testing"

@(test)
test_quakemap_read :: proc(t: ^testing.T) {
	// Test loading a very simple Quake map!
	// This is the example from https://quakewiki.org/wiki/Quake_Map_Format

	test_map_file := `{
"spawnflags" "0"
"classname" "worldspawn"
"wad" "E:\q1maps\Q.wad"
{
( 256 64 16 ) ( 256 64 0 ) ( 256 0 16 ) mmetal1_2 0 0 0 1 1
( 0 0 0 ) ( 0 64 0 ) ( 0 0 16 ) mmetal1_2 0 0 0 1 1
( 64 256 16 ) ( 0 256 16 ) ( 64 256 0 ) mmetal1_2 0 0 0 1 1
( 0 0 0 ) ( 0 0 16 ) ( 64 0 0 ) mmetal1_2 0 0 0 1 1
( 64 64 0 ) ( 64 0 0 ) ( 0 64 0 ) mmetal1_2 0 0 0 1 1
( 0 0 -64 ) ( 64 0 -64 ) ( 0 64 -64 ) mmetal1_2 0 0 0 1 1
}
}
{
"spawnflags" "0"
"classname" "info_player_start"
"origin" "32 32 24"
"test_string" "hello"
}`


	quake_map, err := read(test_map_file)
	defer quake_map_destroy(&quake_map)
	testing.expect_value(t, err, ParseError.None)

	// Check to see if we have a world
	testing.expect_value(t, quake_map.worldspawn.classname, "worldspawn")
	testing.expect_value(t, len(quake_map.worldspawn.solids), 1)
	testing.expect_value(t, len(quake_map.worldspawn.solids[0].faces), 6)

	// Check to see that our one solid is a cube!
	for i in 0 ..< 6 {
		face := quake_map.worldspawn.solids[0].faces[i]
		testing.expect_value(t, len(face.vertices), 4)
	}

	// Check our first face to see if it looks accurate
	first_face := quake_map.worldspawn.solids[0].faces[0]
	testing.expect_value(t, first_face.texture_name, "mmetal1_2")
	testing.expect_value(t, first_face.shift_x, 0.0)
	testing.expect_value(t, first_face.shift_y, 0.0)
	testing.expect_value(t, first_face.rotation, 0.0)
	testing.expect_value(t, first_face.scale_x, 1.0)
	testing.expect_value(t, first_face.scale_y, 1.0)

	// Test vertex positions (vertices are now already Vec3)
	expected_v0 := Vec3{256, 0, 0}
	expected_v1 := Vec3{256, 0, -64}
	expected_v2 := Vec3{256, 256, -64}
	expected_v3 := Vec3{256, 256, 0}

	actual_v0 := first_face.vertices[0]
	actual_v1 := first_face.vertices[1]
	actual_v2 := first_face.vertices[2]
	actual_v3 := first_face.vertices[3]

	testing.expect_value(t, actual_v0, expected_v0)
	testing.expect_value(t, actual_v1, expected_v1)
	testing.expect_value(t, actual_v2, expected_v2)
	testing.expect_value(t, actual_v3, expected_v3)

	// Check our one entity
	testing.expect_value(t, len(quake_map.entities), 1)
	testing.expect_value(t, quake_map.entities[0].classname, "info_player_start")
	testing.expect_value(t, quake_map.entities[0].spawnflags, u32(0))

	// Test entity properties
	origin_prop := get_vec3_property(quake_map.entities[0], "origin")
	expected_origin := Vec3{32, 32, 24}
	if origin_val, ok := origin_prop.?; ok {
		testing.expect_value(t, origin_val, expected_origin)
	} else {
		testing.fail_now(t, "Expected origin property to exist")
	}

	bogus_prop := get_float_property(quake_map.entities[0], "bogus")
	testing.expect_value(t, bogus_prop, nil)

	test_string_prop := get_string_property(quake_map.entities[0], "test_string")
	if test_string_val, ok := test_string_prop.?; ok {
		testing.expect_value(t, test_string_val, "hello")
	} else {
		testing.fail_now(t, "Expected test_string property to exist")
	}
}

// Helper procedures for entity property access
get_string_property :: proc(entity: Entity, key: string) -> Maybe(string) {
	for prop in entity.properties {
		if prop.key == key {
			return prop.value
		}
	}
	return nil
}

get_float_property :: proc(entity: Entity, key: string) -> Maybe(f32) {
	str_val, ok := entity_get_string(entity, key)
	if !ok do return nil

	val, parse_ok := entity_get_float(entity, key)
	if !parse_ok do return nil

	return val
}

get_vec3_property :: proc(entity: Entity, key: string) -> Maybe(Vec3) {
	val, ok := entity_get_vec3(entity, key)
	if !ok do return nil

	return val
}
