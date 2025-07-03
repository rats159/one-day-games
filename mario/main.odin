package main

import "core:mem"
import "core:slice"
import "core:fmt"
raw_level := #load("./assets/level.bin")

Entity :: struct {
    type: u8,
    x,y : u8
}

Level :: struct {
	tiles: [][]u8,
    entities : []Entity
}

read :: proc {
    read_t,
    read_n,
    read_byte,
}

read_n :: proc(data: ^[]byte, n: int) -> []byte {
    out := data[:n]
    data ^= data[n:]
    return out
}

read_byte :: proc(data: ^[]byte) -> byte {
    return read_t(data,byte)
} 

read_t :: proc(data: ^[]byte, $T: typeid ) -> T {
    out: T
    mem.copy(&out,raw_data(data^),size_of(T))
	data^ = data[size_of(T):]
	return out
}

load_level :: proc(raw_data: ^[]byte) {
    version := read(raw_data)
    assert(version == 1)

    width := read(raw_data)
    height := read(raw_data)

    raw_tiles := read(raw_data, int(width) * int(height))

    entity_count := read(raw_data)
    entities := make([]Entity, entity_count)
    
    for &ent in entities {
        ent = read(raw_data, Entity)
    }

    fmt.println(len(raw_data))
}

main :: proc() {
	load_level(&raw_level)
}
