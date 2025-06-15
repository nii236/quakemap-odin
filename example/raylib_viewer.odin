package main

import "../src/quakemap"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
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
loaded_textures: map[string]rl.Texture2D  // Map texture names to loaded textures
sorted_texture_names: [dynamic]string  // Deterministic order of texture names
material_handle_to_name: map[rawptr]string  // Map material handles to their names
camera: rl.Camera3D
camera_yaw: f32
camera_pitch: f32
noclip_mode: bool = false

main :: proc() {
	fmt.println("=== Raylib Quake Map Viewer ===")

	// Initialize Raylib FIRST
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Quake Map Viewer")
	defer rl.CloseWindow()

	// Initialize the map loader
	loader := quakemap.loader_init("textures/")
	defer quakemap.loader_destroy(&loader)

	// Load textures after Raylib is initialized
	load_textures()
	defer delete(sorted_texture_names)
	populate_loader_materials(&loader)

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

	rl.SetTargetFPS(60)
	rl.DisableCursor()

	// Setup camera
	setup_camera()

	// Convert quake meshes to Raylib meshes
	if err := build_raylib_models_from_map(); err != .None {
		fmt.printf("Error converting quake meshes to Raylib: %v\n", err)
		os.exit(1)
	}
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

LoadTexturesError :: enum {
	None,
	OpenDirFailed,
	ReadDirFailed,
	NoTexturesFound,
	TextureLoadFailed,
}

load_textures :: proc() -> LoadTexturesError {
	fmt.println("DEBUG: Starting load_textures")
	loaded_textures = make(map[string]rl.Texture2D)
	sorted_texture_names = make([dynamic]string)
	
	// Load all texture files from textures directory
	texture_dir := "textures"
	fmt.printf("DEBUG: Opening texture directory: %s\n", texture_dir)
	dir_handle, dir_err := os.open(texture_dir)
	if dir_err != os.ERROR_NONE {
		fmt.printf("Failed to open textures directory: %v\n", dir_err)
		return .OpenDirFailed
	}
	defer os.close(dir_handle)
	fmt.println("DEBUG: Directory opened successfully")
	
	file_infos, read_err := os.read_dir(dir_handle, -1)
	if read_err != os.ERROR_NONE {
		fmt.printf("Failed to read textures directory: %v\n", read_err)
		return .ReadDirFailed
	}
	defer delete(file_infos)
	fmt.printf("DEBUG: Found %d files in directory\n", len(file_infos))
	
	// Collect PNG files and sort them for consistent ordering
	png_files := make([dynamic]string)
	defer delete(png_files)
	
	for file_info in file_infos {
		if strings.has_suffix(file_info.name, ".png") {
			append(&png_files, file_info.name)
		}
	}
	
	if len(png_files) == 0 {
		fmt.printf("No PNG textures found in directory\n")
		return .NoTexturesFound
	}

	// Sort the PNG files for deterministic order
	slice.sort(png_files[:])
	
	any_failed := false
	for file_name in png_files {
		fmt.printf("DEBUG: Processing file: %s\n", file_name)
		texture_name := strings.trim_suffix(file_name, ".png")
		texture_path := fmt.tprintf("%s/%s", texture_dir, file_name)
		fmt.printf("DEBUG: Loading texture: %s from %s\n", texture_name, texture_path)
		texture_path_cstr := strings.clone_to_cstring(texture_path, context.temp_allocator)
		fmt.printf("DEBUG: About to call rl.LoadTexture\n")
		texture := rl.LoadTexture(texture_path_cstr)
		fmt.printf("DEBUG: rl.LoadTexture returned, texture.id = %d\n", texture.id)
		if texture.id != 0 {
			loaded_textures[strings.clone(texture_name)] = texture
			append(&sorted_texture_names, strings.clone(texture_name))
			fmt.printf("Loaded texture: %s\n", texture_name)
		} else {
			fmt.printf("Failed to load texture: %s\n", texture_path)
			any_failed = true
		}
	}
	
	fmt.printf("Loaded %d textures in sorted order\n", len(loaded_textures))
	if any_failed {
		return .TextureLoadFailed
	}
	return .None
}

populate_loader_materials :: proc(loader: ^quakemap.MapLoader) {
	// Initialize the handle-to-name mapping
	material_handle_to_name = make(map[rawptr]string)
	
	// Populate the loader's materials map with our loaded textures
	for texture_name, texture in loaded_textures {
		material_info := quakemap.MaterialInfo {
			handle = rawptr(uintptr(texture.id)), // Store texture ID as pointer value
			width = i32(texture.width),
			height = i32(texture.height),
		}
		loader.materials[strings.clone(texture_name)] = material_info
		
		// Store the handle-to-name mapping
		material_handle_to_name[material_info.handle] = strings.clone(texture_name)
		
		fmt.printf("Registered material: %s (%dx%d)\n", texture_name, texture.width, texture.height)
	}
}

BuildRaylibModelsError :: enum {
	None,
	MeshConversionFailed,
}

build_raylib_models_from_map :: proc() -> BuildRaylibModelsError {
	raylib_meshes = make([dynamic]rl.Mesh)
	raylib_models = make([dynamic]rl.Model)

	texture_list := make([dynamic]rl.Texture2D, 0, len(sorted_texture_names))
	for name in sorted_texture_names {
		texture := loaded_textures[name]
		append(&texture_list, texture)
	}
	defer delete(texture_list)

	fallback_texture: rl.Texture2D
	fallback_texture_set := false
	if len(texture_list) > 0 {
		fallback_texture = texture_list[0]
		fallback_texture_set = true
	}

	any_failed := false

	// Convert world geometry
	for quake_mesh in loaded_map.world_geometry {
		if len(quake_mesh.vertices) == 0 || len(quake_mesh.indices) == 0 {
			continue
		}

		raylib_mesh, err := build_raylib_mesh_from_quakemap(quake_mesh)
		if err != .None {
			fmt.printf("Skipping mesh due to conversion error: %v\n", err)
			any_failed = true
			continue
		}
		rl.UploadMesh(&raylib_mesh, false)
		append(&raylib_meshes, raylib_mesh)

		model := rl.LoadModelFromMesh(raylib_mesh)

		if material_name, mat_err := get_material_name_from_mesh(quake_mesh); mat_err == .None {
			texture, tex_err := get_texture_by_name(material_name)
			if tex_err == .None {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = texture
			} else if fallback_texture_set {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = fallback_texture
			} else {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
			}
		} else if fallback_texture_set {
			model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = fallback_texture
		} else {
			model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
		}

		append(&raylib_models, model)
	}

	// Convert entity geometry
	for quake_mesh in loaded_map.entity_geometry {
		if len(quake_mesh.vertices) == 0 || len(quake_mesh.indices) == 0 {
			continue
		}

		raylib_mesh, err := build_raylib_mesh_from_quakemap(quake_mesh)
		if err != .None {
			fmt.printf("Skipping mesh due to conversion error: %v\n", err)
			any_failed = true
			continue
		}
		rl.UploadMesh(&raylib_mesh, false)
		append(&raylib_meshes, raylib_mesh)

		model := rl.LoadModelFromMesh(raylib_mesh)

		if material_name, mat_err := get_material_name_from_mesh(quake_mesh); mat_err == .None {
			texture, tex_err := get_texture_by_name(material_name)
			if tex_err == .None {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = texture
			} else if fallback_texture_set {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = fallback_texture
			} else {
				model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.GREEN
			}
		} else if fallback_texture_set {
			model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].texture = fallback_texture
		} else {
			model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.GREEN
		}

		append(&raylib_models, model)
	}

	if any_failed {
		return .MeshConversionFailed
	}
	return .None
}

BuildRaylibMeshError :: enum {
	None,
	InvalidInput,
	AllocFailed,
}

build_raylib_mesh_from_quakemap :: proc(quake_mesh: quakemap.Mesh) -> (rl.Mesh, BuildRaylibMeshError) {
	mesh := rl.Mesh{}

	vertex_count := i32(len(quake_mesh.vertices))
	triangle_count := i32(len(quake_mesh.indices) / 3)

	if vertex_count == 0 || triangle_count == 0 {
		return rl.Mesh{}, .InvalidInput
	}

	mesh.vertexCount = vertex_count
	mesh.triangleCount = triangle_count

	// Allocate arrays
	mesh.vertices = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 3 * size_of(f32)))
	mesh.normals = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 3 * size_of(f32)))
	mesh.texcoords = cast(^f32)rl.MemAlloc(cast(u32)(vertex_count * 2 * size_of(f32)))
	mesh.colors = cast(^u8)rl.MemAlloc(cast(u32)(vertex_count * 4 * size_of(u8)))
	mesh.indices = cast(^u16)rl.MemAlloc(cast(u32)(len(quake_mesh.indices) * size_of(u16)))

	if mesh.vertices == nil || mesh.normals == nil || mesh.texcoords == nil || mesh.colors == nil || mesh.indices == nil {
		// Free any allocated memory
		if mesh.vertices != nil do rl.MemFree(mesh.vertices)
		if mesh.normals != nil do rl.MemFree(mesh.normals)
		if mesh.texcoords != nil do rl.MemFree(mesh.texcoords)
		if mesh.colors != nil do rl.MemFree(mesh.colors)
		if mesh.indices != nil do rl.MemFree(mesh.indices)
		return rl.Mesh{}, .AllocFailed
	}

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

	return mesh, .None
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

draw_ui :: proc() {
	// Just a simple crosshair for game-like feel
	center_x := i32(SCREEN_WIDTH / 2)
	center_y := i32(SCREEN_HEIGHT / 2)

	// Draw crosshair
	rl.DrawLine(center_x - 10, center_y, center_x + 10, center_y, rl.WHITE)
	rl.DrawLine(center_x, center_y - 10, center_x, center_y + 10, rl.WHITE)

	// Draw FPS counter in top-left corner
	fps := rl.GetFPS()
	fps_text := fmt.tprintf("FPS: %d", fps)
	rl.DrawText(strings.clone_to_cstring(fps_text, context.temp_allocator), 10, 10, 20, rl.YELLOW)
}

GetMaterialNameError :: enum {
	None,
	NoHandle,
	NotFound,
}

// Extract material name from a quakemap mesh
get_material_name_from_mesh :: proc(quake_mesh: quakemap.Mesh) -> (string, GetMaterialNameError) {
	if quake_mesh.material.handle != nil {
		if material_name, found := material_handle_to_name[quake_mesh.material.handle]; found {
			fmt.printf("DEBUG: Material name found via handle: '%s'\n", material_name)
			return material_name, .None
		} else {
			fmt.printf("DEBUG: Material handle %p not found in mapping\n", quake_mesh.material.handle)
			return "", .NotFound
		}
	} else {
		fmt.printf("DEBUG: No material handle in mesh\n")
		return "", .NoHandle
	}
}

GetTextureByNameError :: enum {
	None,
	NotFound,
}

// Get texture by name from loaded textures
get_texture_by_name :: proc(texture_name: string) -> (rl.Texture2D, GetTextureByNameError) {
	if texture, found := loaded_textures[texture_name]; found {
		return texture, .None
	}
	return {}, .NotFound
}