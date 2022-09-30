package main

import "core:fmt"
import "core:os"
import "core:intrinsics"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:bytes"

// I/O helpers

write_ptr :: proc(b: ^bytes.Buffer, data: rawptr, #any_int len: int) {
	bytes.buffer_write(b, mem.byte_slice(data, len));
}

write_slice :: proc(b: ^bytes.Buffer, s: []$T) {
	bytes.buffer_write(b, mem.slice_data_cast([]byte, s));
}

write_u8 :: bytes.buffer_write_byte;

write_u16 :: proc(b: ^bytes.Buffer, v: u16) {
	v := v;
	write_ptr(b, &v, size_of(u16));
}

write_u32 :: proc(b: ^bytes.Buffer, v: u32) {
	v := v;
	write_ptr(b, &v, size_of(u32));
}

write_u64 :: proc(b: ^bytes.Buffer, v: u64) {
	v := v;
	write_ptr(b, &v, size_of(u64));
}

write_u128 :: proc(b: ^bytes.Buffer, v: u128) {
	v := v;
	write_ptr(b, &v, size_of(u128));
}

write_f64 :: proc(b: ^bytes.Buffer, v: f64) {
	v := v;
	write_ptr(b, &v, size_of(f64));
}

write_string :: bytes.buffer_write_string;

write_vec3i :: proc(b: ^bytes.Buffer, v: [3]i32) {
	write_u32(b, transmute(u32)v[0]);
	write_u32(b, transmute(u32)v[1]);
	write_u32(b, transmute(u32)v[2]);
}

write_name :: proc(b: ^bytes.Buffer, s: string) {
	write_u32(b, u32(len(s)));
	write_string(b, s);
}

write_meta_string :: proc(b: ^bytes.Buffer, name: string, s: string) {
	write_name(b, name);
	write_name(b, "string");
	write_name(b, s);
}

write_meta_bool :: proc(b: ^bytes.Buffer, name: string, v: bool) {
	write_name(b, name);
	write_name(b, "bool");
	write_u32(b, 1); // one byte is used to store the bool
	write_u8(b, v ? 1 : 0);
}

write_meta_vec3i :: proc(b: ^bytes.Buffer, name: string, v: [3]i32) {
	write_name(b, name);
	write_name(b, "vec3i");
	write_u32(b, 3 * size_of(i32));
	write_vec3i(b, v);
}

// Tree data structure

VDB :: struct {
	node_5: Node_5,
}

Node_5 :: struct {
	mask:    [512]u64,
	nodes_4: map[u32]^Node_4,
}

Node_4 :: struct {
	mask:    [64]u64,
	nodes_3: map[u32]^Node_3,
}

Node_3 :: struct {
	mask:    [8]u64,
	data:    [512]f16,
}

get_bit_index_4 :: proc(p: [3]u32) -> u32 {
	p := p & u32(4096-1);
	idx_3d := [3]u32{p.x >> 7, p.y >> 7, p.z >> 7};
	idx := idx_3d.z | (idx_3d.y << 5) | (idx_3d.x << 10);
	return idx;
}

get_bit_index_3 :: proc(p: [3]u32) -> u32 {
	p := p & u32(128-1);
	idx_3d := [3]u32{p.x >> 3, p.y >> 3, p.z >> 3};
	idx := idx_3d.z | (idx_3d.y << 4) | (idx_3d.x << 8);
	return idx;
}

get_bit_index_0 :: proc(p: [3]u32) -> u32 {
	p := p & u32(8-1);
	idx_3d := [3]u32{p.x >> 0, p.y >> 0, p.z >> 0};
	idx := idx_3d.z | (idx_3d.y << 3) | (idx_3d.x << 6);
	return idx;
}

set_voxel :: proc(vdb: ^VDB, p: [3]u32, v: f16) {
	node_5 := &vdb.node_5;

	bit_index_4 := get_bit_index_4(p);
	bit_index_3 := get_bit_index_3(p);
	bit_index_0 := get_bit_index_0(p);

	node_4, node_4_found := node_5.nodes_4[bit_index_4];
	if !node_4_found {
		node_4 = new(Node_4);
		map_insert(&node_5.nodes_4, bit_index_4, node_4);
	}

	node_3, node_3_found := node_4.nodes_3[bit_index_3];
	if !node_3_found {
		node_3 = new(Node_3);
		map_insert(&node_4.nodes_3, bit_index_3, node_3);
	}

	node_5.mask[bit_index_4 >> 6] |= 1 << (bit_index_4 & (64-1));
	node_4.mask[bit_index_3 >> 6] |= 1 << (bit_index_3 & (64-1));
	node_3.mask[bit_index_0 >> 6] |= 1 << (bit_index_0 & (64-1));

	node_3.data[bit_index_0] = v;
}

// Routines for writing the actual format

write_node_5_header :: proc(b: ^bytes.Buffer, node: ^Node_5) {
	// Origin of the 5-node
	write_vec3i(b, {0, 0, 0});

	// Child masks
	for word in node.mask do write_u64(b, word);

	// Value masks are zero for now
	for _ in node.mask do write_u64(b, 0);

	// Write uncompressed node values, 6 means no compression
	write_u8(b, 6);
	for i := 0; i < 32768; i += 1 do write_u16(b, 0);
}

write_node_4_header :: proc(b: ^bytes.Buffer, node: ^Node_4) {
	// Child masks
	for word in node.mask do write_u64(b, word);

	// Value masks are zero for now
	for _ in node.mask do write_u64(b, 0);

	// Write uncompressed node values, 6 means no compression
	write_u8(b, 6);
	for i := 0; i < 4096; i += 1 do write_u16(b, 0);
}

write_tree :: proc(b: ^bytes.Buffer, vdb: ^VDB) {
	// We need to write a 1, apparently
	write_u32(b, 1);

	// Root node background value
	write_u32(b, 0);

	// Number of tiles
	write_u32(b, 0);

	// Number of 5-nodes
	write_u32(b, 1);

	node_5 := &vdb.node_5;

	write_node_5_header(b, node_5);

	// Iterate 4-nodes
	for word, word_index in node_5.mask {
		for word := word; word != 0; word &= word - 1 {
			bit_index := u32(word_index) * 64 + u32(intrinsics.count_trailing_zeros(word));

			node_4, node_4_found := node_5.nodes_4[bit_index];
			assert(node_4_found);

			write_node_4_header(b, node_4);

			// Iterate 3-nodes
			for word, word_index in node_4.mask {
				for word := word; word != 0; word &= word - 1 {
					bit_index := u32(word_index) * 64 + u32(intrinsics.count_trailing_zeros(word));

					node_3, node_3_found := node_4.nodes_3[bit_index];
					assert(node_3_found);

					for word in node_3.mask do write_u64(b, word);
				}
			}
		}
	}

	// Iterate 4-nodes
	for word, word_index in node_5.mask {
		for word := word; word != 0; word &= word - 1 {
			bit_index := u32(word_index) * 64 + u32(intrinsics.count_trailing_zeros(word));

			node_4, node_4_found := node_5.nodes_4[bit_index];
			assert(node_4_found);

			// Iterate 3-nodes
			for word, word_index in node_4.mask {
				for word := word; word != 0; word &= word - 1 {
					bit_index := u32(word_index) * 64 + u32(intrinsics.count_trailing_zeros(word));

					node_3, node_3_found := node_4.nodes_3[bit_index];
					assert(node_3_found);

					for word in node_3.mask do write_u64(b, word);

					write_u8(b, 6);
					write_slice(b, node_3.data[:]);
				}
			}
		}
	}
}

write_metadata :: proc(b: ^bytes.Buffer) {
	// Number of entries
	write_u32(b, 4);

	write_meta_string(b, "class", "unknown");
	write_meta_string(b, "file_compression", "none");
	write_meta_bool(b,   "is_saved_as_half_float", true);
	write_meta_string(b, "name", "density");
}

write_transform :: proc(b: ^bytes.Buffer, mat: matrix[4, 4]f64) {
	write_name(b, "AffineMap");

	write_f64(b, mat[0, 0]);
	write_f64(b, mat[1, 0]);
	write_f64(b, mat[2, 0]);
	write_f64(b, 0);

	write_f64(b, mat[0, 1]);
	write_f64(b, mat[1, 1]);
	write_f64(b, mat[2, 1]);
	write_f64(b, 0);

	write_f64(b, mat[0, 2]);
	write_f64(b, mat[1, 2]);
	write_f64(b, mat[2, 2]);
	write_f64(b, 0);

	write_f64(b, mat[0, 3]);
	write_f64(b, mat[1, 3]);
	write_f64(b, mat[2, 3]);
	write_f64(b, 1);
}

write_grid :: proc(b: ^bytes.Buffer, vdb: ^VDB, mat: matrix[4, 4]f64) {
	// Grid name
	write_name(b, "density");

	// Grid type
	write_name(b, "Tree_float_5_4_3_HalfFloat");

	// No instance parent
	write_u32(b, 0);

	// Grid descriptor stream position
	write_u64(b, u64(len(b.buf)) + size_of(u64) * 3);
	write_u64(b, 0);
	write_u64(b, 0);

	// No compression
	write_u32(b, 0);

	write_metadata(b);
	write_transform(b, mat);
	write_tree(b, vdb);
}

write_vdb :: proc(b: ^bytes.Buffer, vdb: ^VDB, mat: matrix[4, 4]f64) {
	// Magic number
	write_slice(b, []byte{0x20, 0x42, 0x44, 0x56, 0x0, 0x0, 0x0, 0x0});

	// File version
	write_u32(b, 224);

	// Library version (we're just gonna pretend we're OpenVDB 8.1)
	write_u32(b, 8); // major
	write_u32(b, 1); // minor

	// We do not have grid offsets
	write_u8(b, 0);

	// Temporary UUID
	write_string(b, "d2b59639-ac2f-4047-9c50-9648f951180c");

	// No metadata for now
	write_u32(b, 0);

	// One grid
	write_u32(b, 1);

	write_grid(b, vdb, mat);
}

main :: proc() {
	b: bytes.Buffer;
	vdb: VDB;

	R :: 128;
	D :: R * 2;

	for z in u32(0)..<D {
		for y in u32(0)..<D {
			for x in u32(0)..<D {
				p := linalg.to_f32([3]u32{x, y, z});
				if linalg.length2(p - R) < R*R {
					set_voxel(&vdb, {x, y, z}, 1.0);
				}
			}
		}
	}

	write_vdb(&b, &vdb, linalg.MATRIX4F64_IDENTITY);

	ok := os.write_entire_file("test.vdb", b.buf[:]);
	if !ok do fmt.println("Failed to write file.");
}
