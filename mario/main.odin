package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"

import rl "vendor:raylib"

raw_level := #load("./assets/level.bin")
tiles_raw := #load("./assets/sprites.png", []u8)
tiles: rl.Texture

Tile_Type :: enum u8 {
	Air                  = 0,
	Polished             = 1,
	Question_Block       = 2,
	Pipe                 = 3,
	Spring               = 8,
	Bricks               = 9,
	Empty_Question_Block = 10,
	Rock                 = 11,
}

Entity_Type :: enum u8 {
	Goomba        = 4,
	Koopa         = 5,
	Koopa_Shell   = 6,
	Flag          = 7,
	Coin          = 12,
	Podobo        = 13,
	Piranha_Plant = 14,
	Mario         = 15,
}

Entity :: struct {
	type:     Entity_Type,
	pos:      [2]f32,
	velocity: [2]f32,
	data:     Entity_Ai_Data,
}

Level :: struct {
	tiles:         []Tile_Type,
	entities:      [dynamic]Entity,
	mario:         Entity,
	width, height: u8,
	die_list:      [dynamic]int, // To be removed at the end of the frame
}

Entity_Ai_Data :: union {
	Goomba_Data,
	Koopa_Data,
	Podobo_Data,
	Koopa_Shell_Data,
}

Koopa_Shell_Data :: struct {
	velocity: f32,
}

Koopa_Data :: struct {
	rightwards: bool,
}

Goomba_Data :: struct {
	rightwards: bool,
}

Podobo_Data :: struct {
	t:      f32,
	origin: [2]f32,
}

read :: proc {
	read_t,
	read_n,
	read_byte,
}

read_n :: proc(data: ^[]byte, n: int) -> []byte {
	out := data[:n]
	data^ = data[n:]
	return out
}

read_byte :: proc(data: ^[]byte) -> byte {
	return read_t(data, byte)
}

read_t :: proc(data: ^[]byte, $T: typeid) -> T {
	out: T
	mem.copy(&out, raw_data(data^), size_of(T))
	data^ = data[size_of(T):]
	return out
}

load_level :: proc(file_data: []byte) -> Level {
	data := slice.clone(file_data)
	version := read(&data)
	assert(version == 1)

	width := read(&data)
	height := read(&data)

	tiles := read(&data, int(width) * int(height))

	entity_count := read(&data)
	entities := make([dynamic]Entity, 0, entity_count)

	mario: Maybe(Entity)

	for _ in 0 ..< entity_count {
		ent_type := read(&data)
		x := read(&data)
		y := read(&data)
		ent := Entity {
			type = Entity_Type(ent_type),
			pos  = {f32(x), f32(y)},
		}
		#partial switch ent.type {
		case .Goomba:
			ent.data = Goomba_Data{}
		case .Podobo:
			ent.data = Podobo_Data {
				origin = ent.pos,
			}
		case .Koopa:
			ent.data = Koopa_Data{}
		case .Koopa_Shell:
			ent.data = Koopa_Shell_Data{}
		}
		if ent.type == .Mario {
			mario = ent
		} else {
			append(&entities, ent)
		}
	}

	assert(mario != nil, "Level has no mario!")

	assert(len(data) == 0) // Every byte read

	return {
		entities = entities,
		tiles = transmute([]Tile_Type)(tiles),
		mario = mario.?,
		width = width,
		height = height,
	}
}

camera: rl.Camera2D
level: Level
TILE_SIZE :: 8

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Mario")

	texture := rl.LoadRenderTexture(256 / 2, 228 / 2)

	tiles = rl.LoadTextureFromImage(
		rl.LoadImageFromMemory(".png", raw_data(tiles_raw), i32(len(tiles_raw))),
	)

	rl.SetTextureFilter(tiles, .POINT)

	level = load_level(raw_level)

	rl.SetTargetFPS(60)

	camera.zoom = 1

	virtualWRatio := (f32)(rl.GetScreenWidth()) / (f32)(texture.texture.width)
	virtualHRatio := (f32)(rl.GetScreenHeight()) / (f32)(texture.texture.height)
	sourceRec := rl.Rectangle {
		0.0,
		0.0,
		(f32)(texture.texture.width),
		-(f32)(texture.texture.height),
	}


	destRec := rl.Rectangle {
		-virtualWRatio,
		-virtualHRatio,
		f32(rl.GetScreenWidth()) + (virtualWRatio * 2),
		f32(rl.GetScreenHeight()) + (virtualHRatio * 2),
	}

	for !rl.WindowShouldClose() {


		destRec = rl.Rectangle {
			f32(rl.GetScreenWidth() / 2) -
			f32(rl.GetScreenHeight()) *
				(f32(texture.texture.width) / f32(texture.texture.height)) /
				2,
			0,
			f32(rl.GetScreenHeight()) * (f32(texture.texture.width) / f32(texture.texture.height)),
			f32(rl.GetScreenHeight()),
		}


		camera.offset = {f32(texture.texture.width) / 2, f32(texture.texture.height) / 2}
		camera.target = level.mario.pos * TILE_SIZE
		camera.target = linalg.clamp(
			camera.target,
			[2]f32{f32(texture.texture.width / 2), f32(texture.texture.height / 2)},
			[2]f32 {
				f32(level.width) * TILE_SIZE - f32(texture.texture.width / 2),
				f32(level.height) * TILE_SIZE - f32(texture.texture.height / 2),
			},
		)
		rl.BeginTextureMode(texture)
		rl.ClearBackground(rl.SKYBLUE)
		
		draw_world()
		tick_world()
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.DrawTexturePro(texture.texture, sourceRec, destRec, {0, 0}, 0, rl.WHITE)
		rl.DrawFPS(0, 0)
		rl.EndDrawing()
	}
}

tile_at :: proc(x, y: $T, loc := #caller_location) -> Tile_Type {
	assert(int(x) + int(y) * int(level.width) < len(level.tiles), loc = loc)
	return level.tiles[int(x) + int(y) * int(level.width)]
}

check_horizontal_collision :: proc(pos, vel: [2]f32) -> (left, right: bool) {
	if pos.x < 0 || pos.x >= f32(level.width) {
		return false, false
	}

	if tile_at(pos.x +.1 + vel.x, pos.y) != .Air {
		left = true
	}

	if tile_at(pos.x + .9 + vel.x, pos.y) != .Air {
		right = true
	}

	return
}

handle_input :: proc() {
	delta: [2]f32

	if rl.IsKeyDown(.D) do delta.x += .025
	if rl.IsKeyDown(.A) do delta.x -= .025

	if rl.IsKeyPressed(.SPACE) {
		if is_on_ground(level.mario.pos) do delta.y -= .35
		else do fmt.println("aire!")
	}

	level.mario.velocity += delta

	level.mario.velocity.x = clamp(level.mario.velocity.x, -.5, .5)

	if !handle_block_hit() {
		level.mario.pos.y += level.mario.velocity.y
	}


	if l, r := check_horizontal_collision(level.mario.pos, level.mario.velocity); !l && !r {
		level.mario.pos.x += level.mario.velocity.x
	} else {
		level.mario.velocity.x = 0
	}
	level.mario.velocity.x *= 0.85
}

is_on_ground :: proc(pos: [2]f32) -> bool {
	if pos.x < 0 || pos.x >= f32(level.width) || pos.y < 0 || pos.y >= f32(level.height) {
		return false
	}
	return tile_at(pos.x + .1, pos.y + 1) != .Air || tile_at(pos.x + 1 - .1, pos.y + 1) != .Air
}

is_on :: proc(pos: [2]f32, type: Tile_Type) -> bool {
	return tile_at(pos.x + .1, pos.y + 1) == type || tile_at(pos.x + 1 - .1, pos.y + 1) == type
}

handle_block_smash :: proc(tile: ^Tile_Type, x, y: int) {
	#partial switch tile^ {
	case .Bricks:
		tile^ = .Air
	case .Question_Block:
		tile^ = .Empty_Question_Block
		append(&level.entities, Entity{type = .Coin, pos = {f32(x), f32(y) - 1}})
	case:
		level.mario.pos.y -= level.mario.velocity.y
	}
}

handle_block_hit :: proc() -> (hit: bool) {
	if level.mario.velocity.y >= 0 do return

	pos := level.mario.pos + level.mario.velocity

	p1 := int(pos.x + .25) + int(pos.y) * int(level.width)
	p2 := int(pos.x + 1 - .25) + int(pos.y) * int(level.width)

	screen_p1 := rl.GetWorldToScreen2D(pos + {.25,0} * TILE_SIZE,camera)
	screen_p2 := rl.GetWorldToScreen2D(pos + {1 - .25,0} * TILE_SIZE,camera)
	rl.DrawRectangleV(linalg.round(screen_p1),1,{0,255,255,255})
	rl.DrawRectangleV(linalg.round(screen_p2),1,{0,255,255,255})

	fmt.println(screen_p1, screen_p2)

	if level.tiles[p1] != .Air {
		handle_block_smash(&level.tiles[p1], int(pos.x), int(pos.y))
		level.mario.velocity.y = 0
		hit = true
	}

	if level.tiles[p2] != .Air {
		handle_block_smash(&level.tiles[p2], int(pos.x + 1), int(pos.y))
		level.mario.velocity.y = 0
		hit = true
	}

	return

}

is_colliding :: proc(a, b: Entity) -> bool {
	return(
		(a.pos.x < b.pos.x + 1) &&
		(a.pos.x + 1 > b.pos.x) &&
		(a.pos.y < b.pos.y + 1) &&
		(a.pos.y + 1 > b.pos.y) \
	)
}

die :: proc() {
	level = load_level(raw_level)
}

handle_player_entity_hit :: proc(entity: ^Entity, index: int) {
	switch entity.type {
	case .Coin:
		append(&level.die_list, index)
	case .Goomba:
		if level.mario.velocity.y > 0 {
			append(&level.die_list, index)

			if rl.IsKeyDown(.SPACE) {
				level.mario.velocity.y = -.25
			} else {
				level.mario.velocity.y = -.125
			}
		} else {
			die()
		}
	case .Piranha_Plant, .Podobo:
		die()
	case .Koopa:
		if level.mario.velocity.y > 0 {
			entity.type = .Koopa_Shell
			entity.data = Koopa_Shell_Data{}
			level.mario.pos.y -= 0.125
			if rl.IsKeyDown(.SPACE) {
				level.mario.velocity.y = -.25
			} else {
				level.mario.velocity.y = -.125
			}
		} else {
			die()
		}
	case .Koopa_Shell:
		if level.mario.velocity.y > 0 {
			if entity.data.(Koopa_Shell_Data).velocity == 0 {
				if abs(level.mario.pos.x - entity.pos.x) > 0.25 {
					(&entity.data.(Koopa_Shell_Data)).velocity =
						level.mario.pos.x < entity.pos.x ? .25 : -.25
				} else {
					append(&level.die_list, index)

				}
			} else {
				(&entity.data.(Koopa_Shell_Data)).velocity = 0
			}
			level.mario.pos.y -= 0.125
			if rl.IsKeyDown(.SPACE) {
				level.mario.velocity.y = -.25
			} else {
				level.mario.velocity.y = -.125
			}
		} else if entity.data.(Koopa_Shell_Data).velocity == 0 {
			(&entity.data.(Koopa_Shell_Data)).velocity =
				level.mario.pos.x < entity.pos.x ? .25 : -.25
			level.mario.pos.x += level.mario.pos.x < entity.pos.x? -.125 : .125
		} else {
			fmt.println(entity.data.(Koopa_Shell_Data).velocity)
			die()
		}
	case .Flag:
		die() // Never ending mario >:)
	case .Mario:
		panic("Mario has been severed from his mortal coil and you are colliding with him")
	}
}

handle_player_entity_hits :: proc() {

	for &ent, i in level.entities {
		if ent.type == .Mario {
			panic("Mario has snuck into the entity list...")
		}

		if is_colliding(ent, level.mario) {
			handle_player_entity_hit(&ent, i)
		}
	}

}

tick_entity :: proc(ent: ^Entity) {
	switch &data in ent.data {
	case Goomba_Data:
		ent.pos.x += (f32(int(data.rightwards)) * 2 - 1) * (f32(1) / 64)
		if left, right := check_horizontal_collision(ent.pos, 0); left || right {
			data.rightwards = !data.rightwards
		}
		apply_gravity(&ent.pos, &ent.velocity)
		ent.pos += ent.velocity
	case Koopa_Data:
		ent.pos.x += (f32(int(data.rightwards)) * 2 - 1) * (f32(1) / 64)
		if left, right := check_horizontal_collision(ent.pos, 0); left || right {
			data.rightwards = !data.rightwards
		}
		apply_gravity(&ent.pos, &ent.velocity)
		ent.pos += ent.velocity
	case Podobo_Data:
		data.t += rl.GetFrameTime()
		ent.pos.y = math.sin(data.t * 2) * 10 + data.origin.y
	case Koopa_Shell_Data:
		if left, right := check_horizontal_collision(ent.pos, {data.velocity, 0}); left || right {
			data.velocity *= -1
		}
		apply_gravity(&ent.pos, &ent.velocity)
		ent.pos.x += data.velocity
		ent.pos.y += ent.velocity.y
	}

}

tick_entities :: proc() {
	for &entity in level.entities {
		tick_entity(&entity)
	}

	#reverse for i in level.die_list {
		unordered_remove(&level.entities, i)
	}
	clear(&level.die_list)
}

apply_gravity :: proc(pos, vel: ^[2]f32) {
	if is_on_ground(pos^) {
		if is_on(pos^, .Spring) {
			vel.y = -.5
		} else {
			vel.y = 0
			pos.y = math.round(pos.y)
		}
	} else {
		vel.y += .0125
	}
}


tick_world :: proc() {
	handle_input()
	if level.mario.pos.x < 0 ||
	   level.mario.pos.x >= f32(level.width) ||
	   level.mario.pos.y < 0 ||
	   level.mario.pos.y >= f32(level.height) {
		die()
	}
	apply_gravity(&level.mario.pos, &level.mario.velocity)

	for do if left, right := check_horizontal_collision(level.mario.pos, level.mario.velocity); left || right {
		// TODO: probably not the best handling this lol
		if left && right {
			if math.round(level.mario.pos.y) > level.mario.pos.y {
				level.mario.pos.y += 0.125
			} else {
				level.mario.pos.y -= 0.125
			}
		}

		if left do level.mario.pos.x += f32(1)/16
		if right do level.mario.pos.x -= f32(1)/16
	} else do break

	tick_entities()
	handle_player_entity_hits()
}

get_tile_source_rect :: proc(index: u8) -> rl.Rectangle {
	return {
		math.floor(f32(index % 4) * (TILE_SIZE)),
		math.floor(f32(index / 4) * (TILE_SIZE)),
		TILE_SIZE - 0.0025,
		TILE_SIZE - 0.0025,
	}
}

draw_tile :: proc(index: Tile_Type, x, y: int) {
	rl.DrawTexturePro(
		tiles,
		get_tile_source_rect(u8(index) % 16),
		{f32(x) * TILE_SIZE, f32(y) * TILE_SIZE, TILE_SIZE, TILE_SIZE},
		{},
		0,
		rl.WHITE,
	)
}

draw_entity :: proc(ent: Entity) {
	rl.DrawTexturePro(
		tiles,
		get_tile_source_rect(u8(ent.type)),
		{
			(ent.type == .Mario ? ent.pos.x : math.round(ent.pos.x * 8) / 8) * TILE_SIZE,
			(ent.type == .Mario ? ent.pos.y : math.round(ent.pos.y * 8) / 8) * TILE_SIZE,
			TILE_SIZE,
			TILE_SIZE,
		},
		{},
		0,
		rl.WHITE,
	)
}

draw_world :: proc() {
	rl.BeginMode2D(camera)
	for tile, i in level.tiles {
		draw_tile(tile, i % int(level.width), i / int(level.width))
	}

	for ent in level.entities {
		draw_entity(ent)
	}

	draw_entity(level.mario)

	rl.EndMode2D()
}
