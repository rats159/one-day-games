package main

import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE})
    rl.InitWindow(1280,720,"Game")

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)
        rl.EndDrawing()
    }

    rl.CloseWindow()
}