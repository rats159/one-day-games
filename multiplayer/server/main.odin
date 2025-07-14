package server

import "../common"
import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import enet "vendor:ENet"

Server_Player :: struct {
	name: string,
	id:   u64,
	pos: [2]f32,
	peer: ^enet.Peer,
}

Server_State :: struct {
	players: map[u64]Server_Player,
}

server_state: Server_State

main :: proc() {
	if enet.initialize() != 0 {
		fmt.eprintfln("Failed to initialize ENet")
		os.exit(1)
	}

	defer enet.deinitialize()

	address: enet.Address
	address.host = enet.HOST_ANY
	address.port = 7777

	server := enet.host_create(&address, 32, 1, 0, 0)

	if server == nil {
		fmt.eprintln("Failed to initialize the server host")
		os.exit(1)
	}

	event: enet.Event

	for {
		for enet.host_service(server, &event, 1000) > 0 {
			#partial switch event.type {
			case .CONNECT:
				fmt.printfln(
					"A new client connected from %x:%d",
					event.peer.address.host,
					event.peer.address.port,
				)
				id := rand.uint64()
				for (id in server_state.players) do id = rand.uint64()
				event.peer.data = rawptr(uintptr(id))
				server_state.players[id] = Server_Player {
					peer = event.peer,
					id   = id,
					name = "<Unknown>",
				}
				fmt.printfln("Someone's here! id %d", id)
				common.send_packet(event.peer, common.Id_Set_Packet{id})

			case .RECEIVE:
				decoded_packet := common.decode(event.packet.data[:event.packet.dataLength])
				#partial switch type in decoded_packet {
				case common.Username_Set_Packet:
					(&server_state.players[u64(uintptr(event.peer.data))]).name = strings.clone(
						type.new_value,
					)
					fmt.printfln("Someone's here named %s!", type.new_value)
				case common.Move_Packet:
					player := &server_state.players[u64(uintptr(event.peer.data))]
					fmt.printfln(
						"Player %s is moving by [%f, %f]",
						player.name,
						type.motion.x,
						type.motion.y,
					)
					player.pos += type.motion
				}
			case .DISCONNECT:
				fmt.printfln(
					"%x:%d disconnected",
					event.peer.address.host,
					event.peer.address.port,
				)
				delete_key(&server_state.players, u64(uintptr(event.peer.data)))

			}
		}

		positions := make([]struct {
				pos: [2]f32,
				id:  u64,
			}, len(server_state.players))
		i := 0
		for id, player in server_state.players {
			positions[i].id = id
			positions[i].pos = player.pos
			i += 1
		}
		broadcast_packet(common.Player_Positions_Packet{u8(len(positions)), positions})
	}

	enet.host_destroy(server)
}

broadcast_packet :: proc(packet: common.Packet) {
	for id, player in server_state.players {
		common.send_packet(player.peer, packet)
	}
}
