package main

import "core:encoding/base32"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"
import "core:os"

VERSION :: 1
TILE_SIZE :: 8
WIDTH :: 100
HEIGHT :: 32

tiles_raw := #load("../assets/sprites.png", []u8)
tiles: rl.Texture
camera: rl.Camera2D
raw_zoom: f32 = 3

level_tiles := [HEIGHT][WIDTH]u8{}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Mario Editor")

	tiles = rl.LoadTextureFromImage(
		rl.LoadImageFromMemory(".png", raw_data(tiles_raw), i32(len(tiles_raw))),
	)
	camera = rl.Camera2D {
		target = {},
		offset = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
		zoom   = 8,
	}

	for !rl.WindowShouldClose() {
		camera.offset = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)}
        rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_world()

        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.S) {
            write_and_save_level()
        }
		rl.EndDrawing()
	}

	rl.CloseWindow()
}

write_and_save_level :: proc() {
    buffer := [dynamic]byte{}
    entities := [dynamic]byte{}
    append(&buffer,VERSION)
    append(&buffer,WIDTH)
    append(&buffer,HEIGHT)

    ent_count: u8 = 0 

    for row,y in level_tiles {
        for cell,x in row {
            // Third bit represents if it's an entity.
            if (cell >> 2) & 1 == 0 {
                append(&buffer, cell)
            } else {
				append(&buffer, 0)
				if ent_count == max(u8) {
                    panic("Too many entities! Max 255.")
                }
                ent_count += 1
                append(&entities,cell)
                append(&entities,byte(x))
                append(&entities,byte(y))
            }
        }
    }

	assert(len(buffer) == WIDTH * HEIGHT + 3)

    file, open_err := os.open("./level.bin", os.O_CREATE | os.O_RDWR)
    if open_err != nil {
        fmt.panicf("%v\n",open_err)
    }
    os.write(file, buffer[:])
    os.write_byte(file, ent_count)
    os.write(file, entities[:])
    os.close(file)
}

get_tile_source_rect :: proc(index: u8) -> rl.Rectangle {
	return {f32(index % 4) * TILE_SIZE, f32(index / 4) * TILE_SIZE, TILE_SIZE, TILE_SIZE}
}

draw_tile :: proc(x, y: u8, index: u8) {
	rl.DrawTexturePro(
		tiles,
		get_tile_source_rect(index),
		{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE, TILE_SIZE, TILE_SIZE},
		{},
		0,
		rl.WHITE,
	)
}

state: struct {
	selected_tile: u8,
}

is_almost :: proc(val, compareto: f32) -> bool {
	return abs(val - compareto) < 1e-2
}

draw_world :: proc() {
	rl.BeginMode2D(camera)
	rl.DrawRectangle(0, 0, WIDTH * TILE_SIZE, HEIGHT * TILE_SIZE, rl.SKYBLUE)
	for x in u8(0) ..< WIDTH {
		for y in u8(0) ..< HEIGHT {
			draw_tile(x, y, level_tiles[y][x])
		}
	}

	if rl.IsMouseButtonDown(.MIDDLE) {
		camera.target -= rl.GetMouseDelta() / camera.zoom
	}

	if rl.IsKeyDown(.LEFT_SHIFT) {
		raw_zoom += rl.GetMouseWheelMove()
		raw_zoom = clamp(raw_zoom, 1, 4)
		camera.zoom = math.pow(2, math.round(raw_zoom))
	} else {
		state.selected_tile += u8(rl.GetMouseWheelMove())
		if state.selected_tile < 0 do state.selected_tile += 16
		if state.selected_tile >= 16 do state.selected_tile -= 16
	}

	hovered_tile := linalg.floor(rl.GetScreenToWorld2D(rl.GetMousePosition(), camera) / TILE_SIZE)
	hovered_tile = linalg.clamp(hovered_tile, [2]f32{0, 0}, [2]f32{WIDTH -1, HEIGHT - 1})
	if state.selected_tile != 0 {
		rl.DrawTexturePro(
			tiles,
			get_tile_source_rect(state.selected_tile),
			{hovered_tile.x * TILE_SIZE, hovered_tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE},
			{},
			0,
			{255, 255, 255, 127},
		)

	} else {
		rl.DrawRectangleLinesEx(
			{hovered_tile.x * TILE_SIZE, hovered_tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE},
			1,
			{255, 255, 255, 127},
		)
	}
	if rl.IsMouseButtonDown(.LEFT) {
		level_tiles[int(hovered_tile.y)][int(hovered_tile.x)] = state.selected_tile
	}

	rl.EndMode2D()
}
