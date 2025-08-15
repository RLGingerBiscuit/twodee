package twodee

import "core:fmt"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

when !ODIN_DEBUG {
	_ :: mem
	_ :: os
}

GRID_CELL_COUNT :: 8
GRID_SIZE :: GRID_CELL_COUNT * TILE_SIZE * TILE_SCALE
GRID_TILE_OFFSET :: (TILE_SIZE * TILE_SCALE / 2)

TILE_SIZE :: 16
TILE_SCALE :: 4
TILE_DIR := #load_directory("../assets/tiles/")

tile_names := [Tile]string {
	.None  = "missing.png",
	.Grass = "grass.png",
	.Stone = "stone.png",
}

Tile :: enum {
	None,
	Grass,
	Stone,
}

Five_Tile :: enum {
	OneCorner,
	TwoCorners,
	Side,
	ThreeCorners,
	Full,
}

Five_Tile_Bit :: enum {
	TL,
	BL,
	TR,
	BR,
}
Five_Tile_Bits :: bit_set[Five_Tile_Bit;u8]

get_five_tile_pos :: proc($flag: Five_Tile) -> rl.Vector2 {
	return {0, TILE_SIZE * cast(f32)flag}
}

get_five_tile_rect :: proc($flag: Five_Tile) -> rl.Rectangle {
	return {0, TILE_SIZE * cast(f32)flag, TILE_SIZE, TILE_SIZE}
}

get_five_tile :: proc(bits: Five_Tile_Bits) -> (pos: [2]int, rot: f32) {
	// odinfmt:disable
	TILE_TO_SOURCE := [len(Five_Tile_Bit) * len(Five_Tile_Bit)]struct {
		pos: [2]int,
		rot:  f32,
	} {
		/*             */ {pos = {-1, -1}, rot =  -1},
		/* TL          */ {pos = { 0,  0}, rot = 180},
		/*    BL       */ {pos = { 0,  0}, rot =  90},
		/* TL BL       */ {pos = { 0,  2}, rot =   0},
		/*       TR    */ {pos = { 0,  0}, rot = 270},
		/* TL    TR    */ {pos = { 0,  2}, rot =  90},
		/*    BL TR    */ {pos = { 0,  1}, rot =   0},
		/* TL BL TR    */ {pos = { 0,  3}, rot =  90},
		/*          BR */ {pos = { 0,  0}, rot =   0},
		/* TL       BR */ {pos = { 0,  1}, rot =  90},
		/*    BL    BR */ {pos = { 0,  2}, rot = 270},
		/* TL BL    BR */ {pos = { 0,  3}, rot =   0},
		/*       TR BR */ {pos = { 0,  2}, rot = 180},
		/* TL    TR BR */ {pos = { 0,  3}, rot = 180},
		/*    BL TR BR */ {pos = { 0,  3}, rot = 270},
		/* TL BL TR BR */ {pos = { 0,  4}, rot =   0},
	}
	// odinfmt:enable

	tile := TILE_TO_SOURCE[transmute(u8)bits]

	return tile.pos, tile.rot
}

try_get_tile :: proc(tiles: []Tile, x, y: int) -> (Tile, bool) {
	if x < 0 || x >= GRID_CELL_COUNT || y < 0 || y >= GRID_CELL_COUNT {
		return {}, false
	}
	return tiles[y * GRID_CELL_COUNT + x], true
}

main :: proc() {
	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			total_leaked := 0
			for _, alloc in tracking_allocator.allocation_map {
				fmt.eprintfln("{}: Leaked {} bytes", alloc.location, alloc.size)
				total_leaked += alloc.size
			}
			for bad_free in tracking_allocator.bad_free_array {
				fmt.eprintfln("{}: Bad free {} at {}", bad_free.memory, bad_free.location)
			}
			if total_leaked > 0 {
				fmt.eprintfln("In total leaked {} bytes", total_leaked)
			}
		}
	}

	fmt.println("Hellope!")

	rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_HIGHDPI, .WINDOW_RESIZABLE})

	rl.InitWindow(1280, 720, "Two Dee")
	defer rl.CloseWindow()

	textures: [Tile]rl.Texture2D
	defer {
		for tex in textures {
			rl.UnloadTexture(tex)
		}
	}

	for tile in Tile {
		for file in TILE_DIR {
			if file.name == tile_names[tile] {
				img := rl.LoadImageFromMemory(".png", raw_data(file.data), cast(i32)len(file.data))
				defer rl.UnloadImage(img)
				tex := rl.LoadTextureFromImage(img)
				rl.SetTextureFilter(tex, .POINT)
				textures[tile] = tex
				break
			}
		}
	}

	tiles: [(TILE_SIZE + 2) * (TILE_SIZE + 2)]Tile
	selected_tile: Tile = .Grass

	for !rl.WindowShouldClose() {
		grid_start: rl.Vector2

		{ 	// update

			if rl.IsKeyPressed(.Q) && int(selected_tile) > int(Tile.None) + 1 {
				selected_tile = cast(Tile)(i32(selected_tile) - 1)
			} else if rl.IsKeyPressed(.E) && int(selected_tile) < len(Tile) - 1 {
				selected_tile = cast(Tile)(i32(selected_tile) + 1)
			}

			rw, rh := rl.GetRenderWidth(), rl.GetRenderHeight()

			grid_start = {f32(rw - GRID_SIZE) / 2, f32(rh - GRID_SIZE) / 2}

			pos := rl.GetMousePosition()
			outer: for y in 0 ..< GRID_CELL_COUNT {
				for x in 0 ..< GRID_CELL_COUNT {
					if (rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)) &&
					   pos.x > grid_start.x + f32(x) * TILE_SIZE * TILE_SCALE &&
					   pos.x < grid_start.x + f32(x + 1) * TILE_SIZE * TILE_SCALE &&
					   pos.y > grid_start.y + f32(y) * TILE_SIZE * TILE_SCALE &&
					   pos.y < grid_start.y + f32(y + 1) * TILE_SIZE * TILE_SCALE {
						tile := &tiles[y * GRID_CELL_COUNT + x]
						if rl.IsMouseButtonDown(.LEFT) && tile^ != selected_tile {
							tile^ = selected_tile
							fmt.printfln("Updated ({}, {}) to {}", x, y, tile^)
						} else if rl.IsMouseButtonDown(.RIGHT) && tile^ != .None {
							tile^ = .None
							fmt.printfln("Updated ({}, {}) to {}", x, y, tile^)
						}
						break outer
					}
				}
			}
		}

		{ 	// render
			rl.BeginDrawing()
			rl.ClearBackground({16, 16, 16, 255})

			rl.DrawText(fmt.ctprintf("Tile: {}", selected_tile), 16, 16, 16, rl.RAYWHITE)

			for xy in 0 ..= GRID_CELL_COUNT {
				// Vertical
				rl.DrawLineV(
					grid_start + {0, f32(xy) * TILE_SIZE * TILE_SCALE},
					grid_start +
					{GRID_CELL_COUNT * TILE_SIZE * TILE_SCALE, f32(xy) * TILE_SIZE * TILE_SCALE},
					rl.RAYWHITE,
				)
				// Horizontal
				rl.DrawLineV(
					grid_start + {f32(xy) * TILE_SIZE * TILE_SCALE, 0},
					grid_start +
					{f32(xy) * TILE_SIZE * TILE_SCALE, GRID_CELL_COUNT * TILE_SIZE * TILE_SCALE},
					rl.RAYWHITE,
				)
			}

			for xy in 0 ..= (GRID_CELL_COUNT + 1) {
				// Vertical
				rl.DrawLineV(
					grid_start - (GRID_TILE_OFFSET) + {0, f32(xy) * TILE_SIZE * TILE_SCALE},
					grid_start -
					(GRID_TILE_OFFSET) +
					{
							(GRID_CELL_COUNT + 1) * TILE_SIZE * TILE_SCALE,
							f32(xy) * TILE_SIZE * TILE_SCALE,
						},
					{rl.BLUE.r, rl.BLUE.g, rl.BLUE.g, 100},
				)
				// Horizontal
				rl.DrawLineV(
					grid_start - (GRID_TILE_OFFSET) + {f32(xy) * TILE_SIZE * TILE_SCALE, 0},
					grid_start -
					(GRID_TILE_OFFSET) +
					{
							f32(xy) * TILE_SIZE * TILE_SCALE,
							(GRID_CELL_COUNT + 1) * TILE_SIZE * TILE_SCALE,
						},
					{rl.BLUE.r, rl.BLUE.g, rl.BLUE.g, 100},
				)
			}

			world: for world_y in 0 ..< GRID_CELL_COUNT {
				for world_x in 0 ..< GRID_CELL_COUNT {
					tile, tile_ok := try_get_tile(tiles[:], world_x, world_y)
					assert(tile_ok)
					if tile == .None {
						continue
					}

					display: for display_dy in 0 ..< 2 {
						for display_dx in 0 ..< 2 {
							display_x := world_x + display_dx
							display_y := world_y + display_dy

							tile_bits: [Tile]Five_Tile_Bits

							tile_br, tile_br_ok := try_get_tile(
								tiles[:],
								display_x - 0,
								display_y - 0,
							)
							tile_tr, tile_tr_ok := try_get_tile(
								tiles[:],
								display_x - 0,
								display_y - 1,
							)
							tile_bl, tile_bl_ok := try_get_tile(
								tiles[:],
								display_x - 1,
								display_y - 0,
							)
							tile_tl, tile_tl_ok := try_get_tile(
								tiles[:],
								display_x - 1,
								display_y - 1,
							)

							if tile_tl == .None &&
							   tile_bl == .None &&
							   tile_tr == .None &&
							   tile_br == .None {continue}

							tile_bits[tile_tl] |= tile_tl_ok ? {.TL} : {}
							tile_bits[tile_bl] |= tile_bl_ok ? {.BL} : {}
							tile_bits[tile_tr] |= tile_tr_ok ? {.TR} : {}
							tile_bits[tile_br] |= tile_br_ok ? {.BR} : {}

							tile_bits[.None] = {}

							for t in Tile {
								if tile_bits[t] == {} {
									continue
								}

								pos, rot := get_five_tile(tile_bits[t])
								assert(pos != {-1, -1} && rot != -1)

								src := rl.Rectangle {
									f32(pos.x) * TILE_SIZE,
									f32(pos.y) * TILE_SIZE,
									TILE_SIZE,
									TILE_SIZE,
								}

								dest := rl.Rectangle {
									grid_start.x + f32(display_x) * TILE_SIZE * TILE_SCALE,
									grid_start.y + f32(display_y) * TILE_SIZE * TILE_SCALE,
									TILE_SIZE * TILE_SCALE,
									TILE_SIZE * TILE_SCALE,
								}

								rl.DrawTexturePro(
									textures[t],
									src,
									dest,
									{GRID_TILE_OFFSET, GRID_TILE_OFFSET},
									rot,
									rl.WHITE,
								)
							}

						}
					}

					// rl.DrawRectangleLinesEx(
					// 	{
					// 		grid_start.x + f32(world_x) * TILE_SIZE * TILE_SCALE,
					// 		grid_start.y + f32(world_y) * TILE_SIZE * TILE_SCALE,
					// 		TILE_SIZE * TILE_SCALE,
					// 		TILE_SIZE * TILE_SCALE,
					// 	},
					// 	2,
					// 	rl.RED,
					// )
				}
			}

			rl.EndDrawing()

			when ODIN_DEBUG {
				for bad_free in tracking_allocator.bad_free_array {
					fmt.eprintfln("Bad free {} at {}\n", bad_free.memory, bad_free.location)
				}
				if len(tracking_allocator.bad_free_array) > 0 {
					os.exit(1)
				}
				clear(&tracking_allocator.bad_free_array)
			}
			free_all(context.temp_allocator)
		}
	}
}
