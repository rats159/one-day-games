package common

import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:slice"
import enet "vendor:ENet"

Packet_Type :: enum u8 {
	Username_Set,
	Message,
	Id_Set,
	Move,
	Player_Positions
}

Packet :: union {
	Username_Set_Packet,
	Message_Packet,
	Id_Set_Packet,
	Move_Packet,
	Player_Positions_Packet,
}

Move_Packet :: struct {
	motion: [2]f32,
}

Id_Set_Packet :: struct {
	id: u64,
}

Username_Set_Packet :: struct {
	new_value: string,
}

Message_Packet :: struct {
	message: string,
}

Player_Positions_Packet :: struct {
	length: u8,
	positions: []struct{
		pos:[2]f32,
		id:u64
	}
}

decoders := [Packet_Type]proc(_: ^[]byte) -> Packet {
	.Username_Set = decode_username_set,
	.Message      = decode_message,
	.Id_Set       = decode_id_set,
	.Move         = decode_move,
	.Player_Positions = decode_player_positions
}

encoders := [Packet_Type]proc(_: Packet, _: ^[dynamic]byte) {
	.Username_Set = encode_username_set,
	.Message      = encode_message,
	.Id_Set       = encode_id_set,
	.Move         = encode_move,
	.Player_Positions = encode_player_positions
}

encode_player_positions :: proc(packet: Packet, stream: ^[dynamic]byte) {
	packet := packet.(Player_Positions_Packet)
	write(stream, packet.length)
	for pos in packet.positions {
		write(stream, pos)
	}
}

decode_player_positions :: proc(stream: ^[]byte) -> Packet {
	length := read(stream, type_of(Player_Positions_Packet{}.length))
	data := read_n(stream, type_of(Player_Positions_Packet{}.positions[0]), int(length))
	return Player_Positions_Packet{length, data}
}

encode_move :: proc(packet: Packet, stream: ^[dynamic]byte) {
	packet := packet.(Move_Packet)
	write(stream, packet.motion)
}
 
decode_move :: proc(stream: ^[]byte) -> Packet {
	dir := read(stream, [2]f32)
	return Move_Packet{dir}
}

encode_id_set :: proc(packet: Packet, stream: ^[dynamic]byte) {
	packet := packet.(Id_Set_Packet)
	write(stream, packet.id)
}

decode_id_set :: proc(stream: ^[]byte) -> Packet {
	id := read(stream, u64)
	return Id_Set_Packet{id}
}

encode_username_set :: proc(packet: Packet, stream: ^[dynamic]byte) {
	packet := packet.(Username_Set_Packet)
	write_string(stream, packet.new_value)
}

decode_username_set :: proc(stream: ^[]byte) -> Packet {
	length := read(stream, u8)
	name := read_n(stream, u8, int(length))
	return Username_Set_Packet{new_value = string(name)}
}

encode_message :: proc(packet: Packet, stream: ^[dynamic]byte) {
	packet := packet.(Message_Packet)
	write_string(stream, packet.message)
}

decode_message :: proc(stream: ^[]byte) -> Packet {
	length := read(stream, u8)
	name := read_n(stream, u8, int(length))
	return Message_Packet{message = string(name)}
}

write_string :: proc(stream: ^[dynamic]byte, str: string) {
	write(stream, u8(len(str)))
	for char in transmute([]u8)str {
		write(stream, char)
	}
}

decode :: proc(packet: []byte) -> Packet {
	packet := packet
	type := read(&packet, Packet_Type)
	return decoders[type](&packet)
}

encode :: proc(packet: Packet) -> []byte {
	packet_buffer := [dynamic]byte{}

	switch type in packet {
	case Username_Set_Packet:
		write(&packet_buffer, Packet_Type.Username_Set)
		encoders[.Username_Set](packet, &packet_buffer)
	case Message_Packet:
		write(&packet_buffer, Packet_Type.Message)
		encoders[.Message](packet, &packet_buffer)
	case Id_Set_Packet:
		write(&packet_buffer, Packet_Type.Id_Set)
		encoders[.Id_Set](packet, &packet_buffer)
	case Move_Packet:
		write(&packet_buffer, Packet_Type.Move)
		encoders[.Move](packet, &packet_buffer)
	case Player_Positions_Packet:
		write(&packet_buffer, Packet_Type.Player_Positions)
		encoders[.Player_Positions](packet, &packet_buffer)
	}

	return packet_buffer[:]
}

read :: proc(stream: ^[]byte, $T: typeid) -> T {
	out: T
	mem.copy(&out, raw_data(stream^), size_of(T))
	stream^ = stream[size_of(T):]
	return out
}

write :: proc(stream: ^[dynamic]byte, thing: $T) {
	append(stream, ..slice.reinterpret([]byte, []T{thing}))
}

read_n :: proc(stream: ^[]byte, $T: typeid, length: int) -> []T {
	out := make([]T, length)
	mem.copy(raw_data(out), raw_data(stream^), size_of(T) * length)
	stream^ = stream[size_of(T) * length:]
	return out
}

send_packet :: proc(peer: ^enet.Peer, packet: Packet) {
	encoded := encode(packet)
	packet := enet.packet_create(raw_data(encoded), uint(len(encoded) + 1), {.RELIABLE})
	enet.peer_send(peer, 0, packet)
	delete(encoded)
}
 