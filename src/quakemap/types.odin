package quakemap

import "core:math/linalg"
import "core:mem"

Vec3 :: linalg.Vector3f32
Vec3d :: linalg.Vector3f64

ParseError :: enum {
	None,
	Unexpected_Token,
	World_Spawn_Not_Found,
	Not_Found,
	Expected_Float,
	Degenerate_Face,
	Unexpected_EOF,
	Expected_Space,
	Expected_Open_Paren,
	Expected_Close_Paren,
	Unexpected_Character,
	File_Not_Found,
	Out_Of_Memory,
}

ErrorInfo :: struct {
	line_number: int,
}

MapLoader :: struct {
	allocator:         mem.Allocator,
	materials:         map[string]MaterialInfo,
	texture_path:      string,
	fallback_material: MaterialInfo,
}

MaterialInfo :: struct {
	handle: rawptr,
	width:  i32,
	height: i32,
}

LoadedMap :: struct {
	world_geometry:  []Mesh,
	entity_geometry: []Mesh,
	spawn_points:    []SpawnPoint,
	map_bounds:      BoundingBox,
	collision_data:  CollisionData,
}

Mesh :: struct {
	vertices: []Vertex,
	indices:  []u32,
	material: MaterialInfo,
	bounds:   BoundingBox,
}

Vertex :: struct {
	position: Vec3,
	normal:   Vec3,
	uv:       [2]f32,
	color:    [4]f32,
}

SpawnPoint :: struct {
	position:   Vec3,
	rotation:   Vec3,
	classname:  string,
	properties: map[string]string,
}

BoundingBox :: struct {
	min: Vec3,
	max: Vec3,
}

CollisionData :: struct {
	solids:       [dynamic]CollisionSolid,
	spatial_grid: SpatialGrid,
}

CollisionSolid :: struct {
	faces:  [dynamic]CollisionFace,
	bounds: BoundingBox,
}

CollisionFace :: struct {
	plane:    Plane,
	vertices: []Vec3,
	bounds:   BoundingBox,
}

SpatialGrid :: struct {
	cells:     [][]int,
	cell_size: f32,
	bounds:    BoundingBox,
}

Property :: struct {
	key:   string,
	value: string,
}

Entity :: struct {
	classname:  string,
	spawnflags: u32,
	properties: [dynamic]Property,
	solids:     [dynamic]Solid,
}

Face :: struct {
	plane:        Plane,
	texture_name: string,
	u_axis:       Vec3,
	v_axis:       Vec3,
	shift_x:      f32,
	shift_y:      f32,
	rotation:     f32,
	scale_x:      f32,
	scale_y:      f32,
	vertices:     []Vec3,
}

Plane :: struct {
	normal: Vec3,
	d:      f32,
}

Solid :: struct {
	faces: [dynamic]Face,
}

QuakeMap :: struct {
	worldspawn: Entity,
	entities:   [dynamic]Entity,
}
