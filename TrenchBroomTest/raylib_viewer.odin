package main

import "../src/quakemap"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import rl "vendor:raylib"

// Constants
SCREEN_WIDTH :: 1200
SCREEN_HEIGHT :: 800
CAMERA_SPEED :: 5.0
MOUSE_SENSITIVITY :: 0.003
MAP_SCALE :: f32(0.1)

// Global state
loaded_map: quakemap.LoadedMap
raylib_meshes: [dynamic]rl.Mesh
raylib_models: [dynamic]rl.Model
camera: rl.Camera3D
camera_yaw: f32
camera_pitch: f32
noclip_mode: bool = false

main :: proc() {
	fmt.println("=== Raylib Quake Map Viewer ===")

	// Initialize the map loader
	loader := quakemap.loader_init("textures/")
	defer quakemap.loader_destroy(&loader)

	// Load the TrenchBroom generated map
	map_file := "test_empty.map"
	fmt.printf("Loading map file: %s\n", map_file)

	map_result, parse_err := quakemap.load_map_from_file(&loader, map_file)
	if parse_err != .None {
		fmt.printf("Error loading map: %v\n", parse_err)
		os.exit(1)
	}
	loaded_map = map_result
	defer quakemap.map_destroy(&loaded_map)

	fmt.println("Map loaded successfully!")

	// Initialize Raylib
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Quake Map Viewer")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	rl.DisableCursor()

	// Setup camera
	setup_camera()

	// Convert quake meshes to Raylib meshes
	convert_quake_meshes_to_raylib()
	defer cleanup_raylib_meshes()

	fmt.println("Starting render loop...")

	// Main game loop
	for !rl.WindowShouldClose() {
		update_camera()

		// Render
		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)

		rl.BeginMode3D(camera)

		// Draw the map
		draw_map()

		rl.EndMode3D()

		// Draw minimal UI
		draw_ui()

		rl.EndDrawing()
	}
}

setup_camera :: proc() {
	// Try to find a spawn point for initial camera position
	initial_pos := rl.Vector3{0, 10, 0}

	if len(loaded_map.spawn_points) > 0 {
		spawn := loaded_map.spawn_points[0]
		// Convert Quake coordinates (X,Y,Z) to Raylib coordinates (X,Z,-Y)
		initial_pos = rl.Vector3 {
			spawn.position.x * MAP_SCALE,
			spawn.position.z * MAP_SCALE + 1, // Quake Z becomes Raylib Y, add height
			-spawn.position.y * MAP_SCALE, // Quake Y becomes -Raylib Z
		}
		fmt.printf("Starting at spawn point: %v (scaled: %v)\n", spawn.position, initial_pos)
	} else {
		// Use map center if no spawn points
		center := (loaded_map.map_bounds.min + loaded_map.map_bounds.max) * 0.5
		initial_pos = rl.Vector3 {
			center.x * MAP_SCALE,
			center.z * MAP_SCALE + 5, // Quake Z becomes Raylib Y, above the map
			-center.y * MAP_SCALE, // Quake Y becomes -Raylib Z
		}
		fmt.printf("Starting at map center: %v (scaled: %v)\n", center, initial_pos)
	}

	camera = rl.Camera3D {
		position   = initial_pos,
		target     = rl.Vector3{initial_pos.x, initial_pos.y - 1, initial_pos.z - 1},
		up         = rl.Vector3{0, 1, 0},
		fovy       = 75.0,
		projection = .PERSPECTIVE,
	}

	// Initialize camera angles
	camera_yaw = 0.0
	camera_pitch = 0.0
}

convert_quake_meshes_to_raylib :: proc() {
	raylib_meshes = make([dynamic]rl.Mesh)
	raylib_models = make([dynamic]rl.Model)

	// Convert world geometry
	for quake_mesh in loaded_map.world_geometry {
		if len(quake_mesh.vertices) == 0 || len(quake_mesh.indices) == 0 {
			continue
		}

		raylib_mesh := convert_mesh_to_raylib(quake_mesh)
		append(&raylib_meshes, raylib_mesh)

		// Create a model from the mesh
		model := rl.LoadModelFromMesh(raylib_mesh)
		model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
		append(&raylib_models, model)
	}

	// Convert entity geometry
	for quake_mesh in loaded_map.entity_geometry {
		if len(quake_mesh.vertices) == 0 || len(quake_mesh.indices) == 0 {
			continue
		}

		raylib_mesh := convert_mesh_to_raylib(quake_mesh)
		append(&raylib_meshes, raylib_mesh)

		// Create a model from the mesh with different color for entities
		model := rl.LoadModelFromMesh(raylib_mesh)
		model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.GREEN
		append(&raylib_models, model)
	}

	fmt.printf("Converted %d meshes to Raylib\n", len(raylib_meshes))
}

convert_mesh_to_raylib :: proc(quake_mesh: quakemap.Mesh) -> rl.Mesh {
	mesh := rl.Mesh{}

	vertex_count := i32(len(quake_mesh.vertices))
	triangle_count := i32(len(quake_mesh.indices) / 3)

	mesh.vertexCount = vertex_count
	mesh.triangleCount = triangle_count

	// Allocate arrays
	mesh.vertices = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 3 * size_of(f32)))
	mesh.normals = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 3 * size_of(f32)))
	mesh.texcoords = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 2 * size_of(f32)))
	mesh.colors = cast(^u8)rl.MemAlloc(cast(u32)(vertex_count * 4 * size_of(u8)))
	mesh.indices = cast(^u16)rl.MemAlloc(cast(u32)(len(quake_mesh.indices) * size_of(u16)))

	// Convert vertices
	vertices_slice := ([^]f32)(mesh.vertices)[:vertex_count * 3]
	normals_slice := ([^]f32)(mesh.normals)[:vertex_count * 3]
	texcoords_slice := ([^]f32)(mesh.texcoords)[:vertex_count * 2]
	colors_slice := ([^]u8)(mesh.colors)[:vertex_count * 4]

	for vertex, i in quake_mesh.vertices {
		base_idx := i * 3
		// Scale and convert coordinates: Quake (X,Y,Z) -> Raylib (X,Z,-Y)
		// Quake uses Z-up, Raylib uses Y-up
		vertices_slice[base_idx + 0] = vertex.position.x * MAP_SCALE
		vertices_slice[base_idx + 1] = vertex.position.z * MAP_SCALE // Quake Z becomes Raylib Y
		vertices_slice[base_idx + 2] = -vertex.position.y * MAP_SCALE // Quake Y becomes -Raylib Z

		// Convert normals the same way
		normals_slice[base_idx + 0] = vertex.normal.x
		normals_slice[base_idx + 1] = vertex.normal.z // Quake Z becomes Raylib Y
		normals_slice[base_idx + 2] = -vertex.normal.y // Quake Y becomes -Raylib Z

		uv_idx := i * 2
		texcoords_slice[uv_idx + 0] = vertex.uv[0]
		texcoords_slice[uv_idx + 1] = vertex.uv[1]

		color_idx := i * 4
		colors_slice[color_idx + 0] = u8(vertex.color[0] * 255)
		colors_slice[color_idx + 1] = u8(vertex.color[1] * 255)
		colors_slice[color_idx + 2] = u8(vertex.color[2] * 255)
		colors_slice[color_idx + 3] = u8(vertex.color[3] * 255)
	}

	// Convert indices
	indices_slice := ([^]u16)(mesh.indices)[:len(quake_mesh.indices)]
	for index, i in quake_mesh.indices {
		indices_slice[i] = u16(index)
	}

	// Upload mesh data to GPU
	rl.UploadMesh(&mesh, false)

	return mesh
}

cleanup_raylib_meshes :: proc() {
	for model in raylib_models {
		rl.UnloadModel(model)
	}
	delete(raylib_models)

	for mesh in raylib_meshes {
		rl.UnloadMesh(mesh)
	}
	delete(raylib_meshes)
}

update_camera :: proc() {
	// Mouse look - proper FPS style
	mouse_delta := rl.GetMouseDelta()

	// Update camera angles based on mouse movement
	camera_yaw += mouse_delta.x * MOUSE_SENSITIVITY
	camera_pitch -= mouse_delta.y * MOUSE_SENSITIVITY // Inverted Y for standard FPS feel

	// Clamp pitch to prevent camera flipping
	camera_pitch = math.clamp(camera_pitch, -math.PI / 2 + 0.1, math.PI / 2 - 0.1)

	// Calculate forward vector from yaw and pitch
	forward := rl.Vector3 {
		math.cos(camera_pitch) * math.cos(camera_yaw),
		math.sin(camera_pitch),
		math.cos(camera_pitch) * math.sin(camera_yaw),
	}

	// Calculate right vector (perpendicular to forward, on XZ plane)
	right := rl.Vector3{math.cos(camera_yaw + math.PI / 2), 0, math.sin(camera_yaw + math.PI / 2)}

	// Update camera target based on position and forward direction
	camera.target = rl.Vector3 {
		camera.position.x + forward.x,
		camera.position.y + forward.y,
		camera.position.z + forward.z,
	}

	// Movement - FPS style with full 3D direction movement
	move_speed := CAMERA_SPEED * rl.GetFrameTime()

	// Use the full forward vector (including vertical component)
	if rl.IsKeyDown(.W) {
		camera.position.x += forward.x * move_speed
		camera.position.y += forward.y * move_speed
		camera.position.z += forward.z * move_speed
	}

	if rl.IsKeyDown(.S) {
		camera.position.x -= forward.x * move_speed
		camera.position.y -= forward.y * move_speed
		camera.position.z -= forward.z * move_speed
	}

	if rl.IsKeyDown(.A) {
		camera.position.x -= right.x * move_speed
		camera.position.z -= right.z * move_speed
	}

	if rl.IsKeyDown(.D) {
		camera.position.x += right.x * move_speed
		camera.position.z += right.z * move_speed
	}

	// Toggle noclip mode with 'N' key
	if rl.IsKeyPressed(.N) {
		noclip_mode = !noclip_mode
		fmt.printf("Noclip mode: %t\n", noclip_mode)
	}

	// Manual vertical movement (only available in noclip mode)
	if noclip_mode {
		if rl.IsKeyDown(.SPACE) {
			camera.position.y += move_speed
		}

		if rl.IsKeyDown(.LEFT_SHIFT) {
			camera.position.y -= move_speed
		}
	}

	// Update target after movement
	camera.target = rl.Vector3 {
		camera.position.x + forward.x,
		camera.position.y + forward.y,
		camera.position.z + forward.z,
	}
}

draw_map :: proc() {
	// Draw all models
	for model in raylib_models {
		rl.DrawModel(model, rl.Vector3{0, 0, 0}, 1.0, rl.WHITE)
	}
}

draw_collision_wireframes :: proc() {
	// Draw collision data as wireframes (scaled and coordinate-converted)
	for solid in loaded_map.collision_data.solids {
		for face in solid.faces {
			if len(face.vertices) < 3 {
				continue
			}

			// Draw face as lines (scaled and coordinate-converted)
			for i in 0 ..< len(face.vertices) {
				start := face.vertices[i]
				end := face.vertices[(i + 1) % len(face.vertices)]

				// Convert Quake (X,Y,Z) to Raylib (X,Z,-Y)
				rl_start := rl.Vector3 {
					start.x * MAP_SCALE,
					start.z * MAP_SCALE,
					-start.y * MAP_SCALE,
				}
				rl_end := rl.Vector3{end.x * MAP_SCALE, end.z * MAP_SCALE, -end.y * MAP_SCALE}

				rl.DrawLine3D(rl_start, rl_end, rl.RED)
			}
		}
	}
}

draw_spawn_points :: proc() {
	for spawn_point in loaded_map.spawn_points {
		// Convert Quake coordinates (X,Y,Z) to Raylib coordinates (X,Z,-Y)
		pos := rl.Vector3 {
			spawn_point.position.x * MAP_SCALE,
			spawn_point.position.z * MAP_SCALE, // Quake Z becomes Raylib Y
			-spawn_point.position.y * MAP_SCALE, // Quake Y becomes -Raylib Z
		}

		// Draw spawn point as a cube (scaled appropriately)
		cube_size := f32(2.0) * MAP_SCALE
		rl.DrawCube(pos, cube_size, cube_size, cube_size, rl.YELLOW)
		rl.DrawCubeWires(pos, cube_size, cube_size, cube_size, rl.BLACK)

		// Draw direction indicator (simple arrow, scaled)
		// Note: Quake rotation might need conversion too, but for now use as-is
		forward := rl.Vector3 {
			math.cos(spawn_point.rotation.y),
			0,
			-math.sin(spawn_point.rotation.y), // Adjust for coordinate system
		}
		arrow_length := f32(3.0) * MAP_SCALE
		arrow_end := rl.Vector3 {
			pos.x + forward.x * arrow_length,
			pos.y,
			pos.z + forward.z * arrow_length,
		}
		rl.DrawLine3D(pos, arrow_end, rl.BLUE)
	}
}

draw_ui :: proc() {
	// Just a simple crosshair for game-like feel
	center_x := i32(SCREEN_WIDTH / 2)
	center_y := i32(SCREEN_HEIGHT / 2)

	// Draw crosshair
	rl.DrawLine(center_x - 10, center_y, center_x + 10, center_y, rl.WHITE)
	rl.DrawLine(center_x, center_y - 10, center_x, center_y + 10, rl.WHITE)
}
