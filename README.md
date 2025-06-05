# Quake Map Loader for Odin

A Quake .map file parser and geometry builder written in Odin, ported from Zig (https://raw.githubusercontent.com/fabioarnold/3d-game/refs/heads/master/src/QuakeMap.zig).

## Overview

This library provides functionality to load and process Quake .map files (as used by TrenchBroom and other Quake editors) into renderable geometry and collision data. It handles the complete pipeline from parsing map entities to generating optimized meshes.

## Features

- **Map Parsing**: Complete parser for Quake .map format
- **Geometry Generation**: Convert brush entities into triangle meshes
- **Collision Detection**: Generate collision data for physics systems
- **Material Management**: Organize geometry by texture/material
- **Memory Efficient**: Uses arena allocators for optimal memory usage
- **Entity Processing**: Extract spawn points and entity properties

## Quick Start

```odin
package main

import "quakemap"

main :: proc() {
    // Initialize the map loader
    loader := quakemap.loader_init("textures/")
    defer quakemap.loader_destroy(&loader)

    // Load a map file
    loaded_map, err := quakemap.load_map_from_file(&loader, "maps/test.map")
    if err != .None {
        fmt.println("Failed to load map:", err)
        return
    }
    defer quakemap.map_destroy(&loaded_map)

    // Access world geometry
    for mesh in loaded_map.world_geometry {
        // Render mesh...
    }

    // Access spawn points
    for spawn in loaded_map.spawn_points {
        fmt.printf("Spawn at %v\n", spawn.position)
    }
}
```

## API Reference

### Core Types

#### `LoadedMap`

The main result structure containing all parsed map data:

- `world_geometry: []Mesh` - Renderable geometry for world brushes
- `entity_geometry: []Mesh` - Renderable geometry for entity brushes
- `spawn_points: []SpawnPoint` - Player/item spawn locations
- `collision_data: CollisionData` - Physics collision data

#### `Mesh`

Renderable geometry data:

- `vertices: []Vertex` - Vertex data with position, normal, UV, color
- `indices: []u32` - Triangle indices
- `material: MaterialInfo` - Associated texture/material
- `bounds: BoundingBox` - Mesh bounding box

#### `SpawnPoint`

Entity spawn information:

- `position: Vec3` - World position
- `rotation: Vec3` - Euler angles
- `classname: string` - Entity class (e.g., "info_player_start")
- `properties: map[string]string` - Custom entity properties

### Functions

#### Map Loading

```odin
loader_init :: proc(texture_path: string, allocator := context.allocator) -> MapLoader
loader_destroy :: proc(loader: ^MapLoader)
load_map_from_file :: proc(loader: ^MapLoader, filepath: string) -> (LoadedMap, ParseError)
load_map_from_string :: proc(loader: ^MapLoader, data: string) -> (LoadedMap, ParseError)
map_destroy :: proc(quake_map: ^LoadedMap)
```

#### Collision Detection

```odin
check_collision :: proc(collision_data: ^CollisionData, position: Vec3, size: Vec3) -> bool
find_floor_height :: proc(collision_data: ^CollisionData, x, z: f32) -> (height: f32, found: bool)
```

### Supported Features

- **Brushes**: Convex polyhedra defined by planes
- **Entities**: Point and brush entities with properties
- **Texturing**: UV mapping with rotation, scaling, and offset
- **Materials**: Texture references and material properties

### Map Structure

```
{
"classname" "worldspawn"
{
( 0 0 0 ) ( 64 0 0 ) ( 0 64 0 ) texture_name 0 0 0 1 1
( ... more faces ... )
}
}
{
"classname" "info_player_start"
"origin" "32 32 16"
}
```

## Error Handling

All parsing functions return a `ParseError` enum:

- `.None` - Success
- `.Unexpected_Token` - Invalid syntax
- `.World_Spawn_Not_Found` - Missing worldspawn entity
- `.File_Not_Found` - Invalid file path
- `.Out_Of_Memory` - Allocation failure
