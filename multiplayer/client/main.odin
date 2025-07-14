package client

import "core:slice"
import "../common"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"
import enet "vendor:ENet"
import rl "vendor:raylib"

main :: proc() {
	username := input("username: ")
	defer delete(username)

	if enet.initialize() != 0 {
		fmt.eprintfln("Failed to initialize ENet")
		os.exit(1)
	}

	defer enet.deinitialize()

	client := enet.host_create(nil, 1, 1, 0, 0)

	if client == nil {
		fmt.eprintfln("Failed to initialize the client host")
		os.exit(1)
	}

	address: enet.Address

	enet.address_set_host(&address, "127.0.0.1")
	address.port = 7777

	server := enet.host_connect(client, &address, 1, 0)

	if server == nil {
		fmt.eprintfln("Failed to connect to a peer")
		os.exit(1)
	}

	event: enet.Event

	if enet.host_service(client, &event, 5000) > 0 && event.type == .CONNECT {
		fmt.println("Connection to 127.0.0.1:7777 succeeded")
	} else {
		enet.peer_reset(server)
		fmt.eprintln("Failed to connect")

		os.exit(0)
	}

	world := World {
		client = client,
		server = server,
		player = {pos = {0, 0}},
	}

	common.send_packet(server, common.Username_Set_Packet{username})

	play_game(&world)

	enet.peer_disconnect(server, 0)
	for enet.host_service(client, &event, 3000) > 0 {
		#partial switch event.type {
		case .RECEIVE:
			enet.packet_destroy(event.packet)
		case .DISCONNECT:
			fmt.println("Disconnection succeeded")
		}
	}
}

World :: struct {
	client: ^enet.Host,
	server: ^enet.Peer,
	player: Player,
	player_positions: []struct{
		pos:[2]f32,
		id:u64
	}
}

Player :: struct {
	pos: [2]f32,
	id:  u64,
}

network_thread_proc :: proc(world: ^World) {
	event: enet.Event

	for {
		for enet.host_service(world.client, &event, 1000 / 20) > 0 {
			#partial switch event.type {
			case .RECEIVE:
				packet := common.decode(event.packet.data[:event.packet.dataLength])
				#partial switch type in packet {
				case common.Id_Set_Packet:
					fmt.printfln("Mister server says my id is %d", type.id)
					world.player.id = type.id

				case common.Player_Positions_Packet:
					if world.player_positions != nil do delete(world.player_positions)
					world.player_positions = slice.clone(type.positions)
				}
			}
		}
	}
}

play_game :: proc(world: ^World) {
	rl.InitWindow(800, 800, "It's multiplayin time")
	rl.SetTargetFPS(60)

	network_thread := thread.create_and_start_with_poly_data(world, network_thread_proc)

	for !rl.WindowShouldClose() {
		check_input(world)

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
		draw_player(world.player)
		
		for player in world.player_positions {
			rl.DrawCircleV(player.pos,10,rl.BLUE)
		}
		
		rl.EndDrawing()

	}

	rl.CloseWindow()

	thread.terminate(network_thread, 0)
}

draw_player :: proc(player: Player) {
	rl.DrawCircleV(player.pos, 10, rl.RED)
}

move :: proc(world: ^World, direction: [2]f32) {
	world.player.pos += direction
	common.send_packet(world.server, common.Move_Packet{direction})
}

check_input :: proc(world: ^World) {
	if rl.IsKeyDown(.W) do move(world, {0, -5})
	if rl.IsKeyDown(.S) do move(world, {0, 5})
	if rl.IsKeyDown(.A) do move(world, {-5, 0})
	if rl.IsKeyDown(.D) do move(world, {5, 0})
}

input :: proc(prompt: string = "", trim := true) -> string {
	fmt.print(prompt)

	buf: [256]byte
	n, err := os.read(os.stdin, buf[:])

	if err != nil {
		fmt.panicf("Error reading: ", err)
	}
	str := string(buf[:n])

	if trim {
		str = strings.trim(str, "\r\n\t ")
	}

	return strings.clone(str)
}
