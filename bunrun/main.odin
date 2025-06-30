package game1

import "core:math/noise"
import "core:math/rand"
import "core:time"
import rl "vendor:raylib"

TILE_SIZE :: 8
TILES_X :: 33
TILES_Y :: 33

TILE_IMAGE := #load("./assets/tiles.png", []byte)

Tile :: distinct u8

Level :: struct {
	tiles:     [TILES_Y][TILES_X]Tile,
	bunnypos:  [2]int,
	possumpos: [2]int,
	coldness:  u8,
	seed:      i64,
}

Game_State :: enum {
	Menu,
	Playing,
	Lost,
	Won,
}

state := Game_State.Menu

level := Level{}

tilemap: rl.Texture
start: time.Time

setup :: proc() {
	start = time.now()
	level.seed = i64(rand.uint64())
	generate_level(&level)
	level.coldness = 0
	state = Game_State.Playing
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "bunrun")
	rl.SetTargetFPS(60)

	tilemap = rl.LoadTextureFromImage(
		rl.LoadImageFromMemory(".png", raw_data(TILE_IMAGE), i32(len(TILE_IMAGE))),
	)
	surface := rl.LoadRenderTexture(TILE_SIZE * TILES_X, TILE_SIZE * TILES_Y)

	scale_ratio: f32
	if rl.GetScreenWidth() > rl.GetScreenHeight() {
		scale_ratio = f32(rl.GetScreenHeight()) / f32(surface.texture.height)
	} else {
		scale_ratio = f32(rl.GetScreenWidth()) / f32(surface.texture.width)
	}

	sourceRec := rl.Rectangle{0.0, 0.0, f32(surface.texture.width), -f32(surface.texture.height)}

	for !rl.WindowShouldClose() {
		origin: [2]f32
		if rl.GetScreenWidth() > rl.GetScreenHeight() {
			scale_ratio = f32(rl.GetScreenHeight()) / f32(surface.texture.height)
			origin.x = -f32(rl.GetScreenWidth()) / 2 + f32(surface.texture.width) * scale_ratio / 2
		} else {
			scale_ratio = f32(rl.GetScreenWidth()) / f32(surface.texture.width)
			origin.y =
				-f32(rl.GetScreenHeight()) / 2 + f32(surface.texture.height) * scale_ratio / 2
		}

		destRec := rl.Rectangle {
			0,
			0,
			f32(surface.texture.width) * scale_ratio,
			f32(surface.texture.height) * scale_ratio,
		}
		if state == .Menu {
			rl.BeginDrawing()
			rl.ClearBackground(rl.WHITE)
			centered_text("Bun run!", 48)
			centered_text("Press space to begin", 24, {0, 24})
			rl.EndDrawing()
			if rl.IsKeyPressed(.SPACE) {
				setup()
			}
		} else if state == .Playing {
			handle_input()
			rl.BeginTextureMode(surface)
			rl.ClearBackground(rl.WHITE)
			draw_level()
			rl.EndTextureMode()

			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)
			rl.DrawTexturePro(surface.texture, sourceRec, destRec, origin, 0.0, rl.WHITE)
			rl.DrawRectanglePro(destRec, origin, 0, {255, 255, 255, level.coldness})
			rl.EndDrawing()
			if level.bunnypos == level.possumpos {
				state = .Won
			} else if (level.tiles[level.bunnypos.y][level.bunnypos.x] >> 1) & 1 == 1 {
				level.coldness += 1
			} else {
				if level.coldness > 0 {
					level.coldness -= 1
				}
			}

			if level.coldness == max(u8) {
				state = .Lost
			}
		} else if state == .Won {
			rl.BeginDrawing()
			rl.DrawRectanglePro(destRec, origin, 0, rl.LIME)
			centered_text("you win! :3", 48)
			centered_text("press R to go again!", 48, {0, 48})
			rl.EndDrawing()

			if rl.IsKeyPressed(.R) do setup()
		} else if state == .Lost {
			rl.BeginDrawing()
			rl.DrawRectanglePro(destRec, origin, 0, rl.WHITE)
			centered_text("you FROZE! >:(", 48)
			centered_text("press R to restart", 48, {0, 48})

			rl.EndDrawing()

			if rl.IsKeyPressed(.R) do setup()
		}


	}
}

centered_text :: proc(text: cstring, size: i32, offset: [2]i32 = {0, 0}) {
	text_width := rl.MeasureText(text, size)
	rl.DrawText(
		text,
		(rl.GetScreenWidth() / 2) - text_width / 2 + offset.x,
		(rl.GetScreenHeight() / 2) - size / 2 + offset.y,
		size,
		rl.BLACK,
	)
}

handle_input :: proc() {
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		try_move(.Right, rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D))
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		try_move(.Left, rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A))
	}
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		try_move(.Up, rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W))
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		try_move(.Down, rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S))
	}
}

Direction :: enum {
	Up,
	Left,
	Down,
	Right,
}

MOVE_HOLD_COOLDOWN :: f64(1) / 16

last_move: time.Time

try_move :: proc(dir: Direction, held: bool) {
	if !held && time.duration_seconds(time.since(last_move)) < MOVE_HOLD_COOLDOWN {
		return
	}

	new_pos: [2]int
	switch dir {
	case .Up:
		new_pos = level.bunnypos + {0, -1}
	case .Down:
		new_pos = level.bunnypos + {0, 1}
	case .Left:
		new_pos = level.bunnypos + {-1, 0}
	case .Right:
		new_pos = level.bunnypos + {1, 0}
	}

	if is_moveable(new_pos) {
		level.bunnypos = new_pos
		last_move = time.now()
	}
}

is_moveable :: proc(pos: [2]int) -> bool {
	if pos.x < 0 || pos.x >= TILES_X || pos.y < 0 || pos.y >= TILES_Y {
		return false
	}

	if level.tiles[pos.y][pos.x] == 1 || level.tiles[pos.y][pos.x] == 3 {
		return false
	}

	return true
}

generate_maze :: proc(level: ^Level) {
	dfs(&level.tiles, 1, 1)
}

dfs :: proc(maze: ^[TILES_Y][TILES_X]Tile, cx, cy: int) {
	maze[cy][cx] = 0

	directions := [len(Direction)][2]int {
		Direction.Up    = {0, -1},
		Direction.Down  = {0, 1},
		Direction.Left  = {-1, 0},
		Direction.Right = {1, 0},
	}

	rand.shuffle(directions[:])

	for d in directions {
		nx := cx + d.x * 2
		ny := cy + d.y * 2

		if (ny > 0 && ny < len(maze) - 1 && nx > 0 && nx < len(maze[0]) - 1) {
			if (maze[ny][nx] == 1) {
				maze[cy + d.y][cx + d.x] = 0
				dfs(maze, nx, ny)
			}
		}
	}
}

generate_level :: proc(level: ^Level) {
	for &row, _ in level.tiles {
		for &cell, _ in row {
			cell = 1
		}
	}

	generate_maze(level)

	for &row, _ in level.tiles[1:TILES_Y - 1] {
		for &cell, _ in row[1:TILES_X - 1] {
			if rand.float32() < f32(1) / 8 {
				cell = 0
			}
		}
	}

	level.bunnypos = {1, 1}
	level.possumpos = {TILES_X - 2, TILES_Y - 2}
}

FULL_FREEZE_TIME :: TILES_X

draw_level :: proc() {
	for &row, y in level.tiles {
		for &cell, x in row {
			draw_tile(cell, x, y)
			freeze_ratio := time.duration_seconds(time.since(start)) / FULL_FREEZE_TIME
			freeze_ratio += f64(noise.noise_2d(level.seed, {f64(x), f64(y)})) / 10
			freeze_ratio -= .05
			cell_ratio := f64(x + y) / (TILES_X + TILES_Y)
			if freeze_ratio > cell_ratio {
				cell |= 2
			}
		}
	}
	draw_tile(15, level.bunnypos.x, level.bunnypos.y)
	draw_tile(14, level.possumpos.x, level.possumpos.y)
}

draw_tile :: proc(cell: Tile, x, y: int) {
	rl.DrawTexturePro(
		tilemap,
		get_tile_position(cell),
		{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE, TILE_SIZE, TILE_SIZE},
		{},
		0,
		rl.WHITE,
	)
}

get_tile_position :: proc(tile: Tile) -> rl.Rectangle {
	return {f32(tile % 4) * TILE_SIZE, f32(tile / 4) * TILE_SIZE, TILE_SIZE, TILE_SIZE}
}
