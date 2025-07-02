package main

import clay "../../C/clay/bindings/odin/clay-odin"
import "core:fmt"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

Changer :: struct($T: typeid) {
	value:  ^T,
	change: T,
}

Custom :: struct {
	effect: proc(_: ..any),
}

Upgrade_Effect :: union {
	Changer(u128),
	Changer(f32),
	Ticker,
	Custom,
}

Upgrade :: struct {
	name:       string,
	cost:       u128,
	effect:     Upgrade_Effect,
	cost_scale: f64,
}


load_font :: proc(data: []byte, size: i32) -> rl.Font {
	font := rl.LoadFontFromMemory(".ttf", raw_data(data), i32(len(data)), size, nil, 0)
	rl.SetTextureFilter(font.texture, .BILINEAR)
	append(&raylib_fonts, font)
	return font
}

Ticker :: struct {
	progress: f32,
	duration: f32,
	name:     string,
	yield:    u128,
}

state: struct {
	cookies:           u128,
	cookies_per_click: u128,
	upgrades:          [dynamic]Upgrade,
	tickers:           [dynamic]Ticker,
}

font := #load("./assets/NotoSans-Regular.ttf", []byte)

reset_state :: proc() {
	state = {}
	state.cookies_per_click = 1

	append(
		&state.upgrades,
		Upgrade {
			name = "+1 Clicker",
			effect = Ticker{name = "Clicker", duration = 1, yield = 1},
			cost = 10,
			cost_scale = 1.5,
		},
	)
	append(
		&state.upgrades,
		Upgrade {
			name = "+1 Grandma",
			effect = Ticker{name = "Grandma", duration = 2, yield = 5},
			cost = 50,
			cost_scale = 1.25,
		},
	)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "Cookie clicker")

	min_mem := uint(clay.MinMemorySize())
	arena := clay.CreateArenaWithCapacityAndMemory(min_mem, make([^]byte, min_mem))
	clay.Initialize(arena, {1280, 720}, {})
	clay.SetMeasureTextFunction(measure_text, nil)
	load_font(font, 24)

	reset_state()

	for !rl.WindowShouldClose() {
		clay.SetLayoutDimensions({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
		clay.SetPointerState(rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
		clay.UpdateScrollContainers(false, rl.GetMouseWheelMoveV(), rl.GetFrameTime())
		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
		draw_game()
		rl.EndDrawing()
	}

	rl.CloseWindow()
}

tick_tickers :: proc() {
	for &ticker in state.tickers {
		ticker.progress += rl.GetFrameTime()
		if ticker.progress > ticker.duration {
			ticker.progress = 0
			state.cookies += ticker.yield
		}
	}
}

draw_game :: proc() {
	clay.BeginLayout()
	if clay.UI()(
	{
		layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}},
		border = {color = {0, 0, 0, 255}, width = {0, 0, 0, 0, 1}},
	},
	) {
		tick_tickers()
		draw_cookie()
		draw_tickers()
		draw_upgrades()
	}
	cmds := clay.EndLayout()
	clay_raylib_render(&cmds)
}

Transform :: struct {
	scale:     [2]f32,
	rotation:  f32,
	translate: [2]f32,
}

buy_upgrade :: proc(upgrade: ^Upgrade, index: int) -> bool {
	assert(state.cookies >= upgrade.cost)

	switch effect in upgrade.effect {
	case Changer(f32):
		effect.value^ += effect.change
	case Changer(u128):
		effect.value^ += effect.change
	case Ticker:
		append(&state.tickers, effect)
	case Custom:
		effect.effect()
	}

	state.cookies -= upgrade.cost

	if upgrade.cost_scale == 0 {
		ordered_remove(&state.upgrades, index)
		return true
	} else {
		upgrade.cost = u128(f64(upgrade.cost) * upgrade.cost_scale)
	}

	return false
}

draw_upgrade :: proc(upgrade: ^Upgrade, index: int) -> (return_val: bool){
	if clay.UI()(
	{
		layout = {sizing = {width = clay.SizingGrow({})}, padding = clay.PaddingAll(8)},
		backgroundColor = upgrade.cost > state.cookies ? {128, 128, 128, 255} : clay.Hovered() ? {192, 192, 192, 255} : {},
	},
	) {
		clay.TextDynamic(upgrade.name, &text_config)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {}
		clay.TextDynamic(fmt.tprintf("$%d", upgrade.cost), &text_config)
		if clay.Hovered() {
			if upgrade.cost <= state.cookies {
				rl.SetMouseCursor(.POINTING_HAND)
				if rl.IsMouseButtonPressed(.LEFT) {
					return_val = buy_upgrade(upgrade, index)
				}
			} else {
				rl.SetMouseCursor(.NOT_ALLOWED)
			}
		}
	}

	return
}

draw_upgrades :: proc() {
	if clay.UI()(
	{
		layout = {sizing = {width = clay.SizingPercent(.25)}, layoutDirection = .TopToBottom},
		border = {width = {0, 0, 0, 1, 1}, color = {0, 0, 0, 255}},
	},
	) {
		for i := 0; i < len(state.upgrades); i += 1{
			 if draw_upgrade(&state.upgrades[i], i) {
				i -= 1
			 }
		}
	}
}

text_config := clay.TextElementConfig {
	textColor = {0, 0, 0, 255},
	fontId    = 0,
	fontSize  = 24,
}

draw_ticker :: proc(ticker: Ticker, i: int) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {
		clay.TextDynamic(ticker.name, &text_config)
		id := clay.ID_LOCAL("parent", u32(i))
		if clay.UI()(
		{
			layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}},
			id = id,
			backgroundColor = {0, 0, 255, 255},
		},
		) {
			bounds := clay.GetElementData(id).boundingBox
			if clay.UI()(
			{
				floating = {attachTo = .Parent, clipTo = .AttachedParent},
				layout = {
					sizing = {
						clay.SizingFixed(bounds.width * ticker.progress / ticker.duration),
						clay.SizingFixed(bounds.height),
					},
				},
				backgroundColor = {255, 0, 0, 255},
			},
			) {

			}

		}
	}
}

draw_tickers :: proc() {
	if clay.UI()(
	{
		layout = {
			sizing = {width = clay.SizingPercent(.5)},
			childAlignment = {.Center, .Top},
			layoutDirection = .TopToBottom,
		},
	},
	) {
		clay.TextDynamic(fmt.tprintf("Cookies: %d", state.cookies), &text_config)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow({})}}}) {
			id := clay.ID("tickers")
			if clay.UI()(
			{
				layout = {
					sizing = {width = clay.SizingGrow({})},
					childAlignment = {.Center, .Top},
					layoutDirection = .TopToBottom,
				},
				id = id,
				backgroundColor = {255, 0, 255, 255},
				clip = {vertical = true, childOffset = clay.GetScrollOffset()},
			},
			) {
				for ticker, i in state.tickers {
					draw_ticker(ticker, i)
				}
			}
			scrolldata := clay.GetScrollContainerData(id)
			fmt.println(scrolldata)
			if scrolldata.scrollContainerDimensions.height < scrolldata.contentDimensions.height {
				if clay.UI()(
				{
					layout = {sizing = {clay.SizingFixed(12), clay.SizingGrow({})}},
					backgroundColor = {255, 0, 0, 255},
				},
				) {
					if clay.UI()(
					{
						layout = {
							sizing = {
								clay.SizingGrow({}),
								clay.SizingFixed(
									scrolldata.scrollContainerDimensions.height /
									scrolldata.contentDimensions.height *
									scrolldata.scrollContainerDimensions.height,
								),
							},
						},
						floating = {
							attachTo = .Parent,
							offset = {1 = -scrolldata.scrollPosition.y},
						},
						backgroundColor = {0, 255, 0, 255},
					},
					) {}
				}
			}
		}
	}
}

draw_cookie :: proc() {
	if clay.UI()(
	{
		layout = {
			sizing = {clay.SizingPercent(.25), clay.SizingGrow({})},
			childAlignment = {.Center, .Center},
		},
	},
	) {
		transform := new(Transform, context.temp_allocator)
		if clay.UI()(
		{
			layout = {sizing = {width = clay.SizingPercent(.5)}},
			cornerRadius = clay.CornerRadiusAll(9999),
			backgroundColor = {255, 191, 127, 255},
			aspectRatio = {1},
			userData = transform,
		},
		) {
			if clay.Hovered() {
				if rl.IsMouseButtonPressed(.LEFT) {
					state.cookies += state.cookies_per_click
				}
				if rl.IsMouseButtonDown(.LEFT) {
					transform.scale = .9
				} else {
					transform.scale = .95
				}
			} else {
				transform.scale = 1
			}
		}
	}
}
