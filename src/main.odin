package twodee

import sa "core:container/small_array"
import "core:encoding/cbor"
import "core:fmt"
import "core:mem"
import "core:os/os2"
import "core:slice"
import rl "vendor:raylib"

when !ODIN_DEBUG {
	_ :: mem
	_ :: os2
}

GRID_CELL_COUNT :: 10
GRID_SIZE :: GRID_CELL_COUNT * GRID_TILE_SIZE
GRID_TILE_OFFSET :: (GRID_TILE_SIZE / 2)
GRID_TILE_SCALE :: 2
GRID_TILE_SIZE :: TILE_SIZE * GRID_TILE_SCALE

// Seconds
LOAD_SAVE_TIMER :: 2
LOAD_SAVE_TIMER_FADE :: 0.5

WORLD_PATH :: "world.td"

TILE_SIZE :: 32
TILE_DIR := #load_directory("../assets/tiles/")

UNDO_STEPS :: 128

Tile :: enum {
	None,
	Grass,
	Dirt,
	Stone,
	Sand,
	Water,
}

tile_names := [Tile]string {
	.None  = "missing.png",
	.Grass = "grass.png",
	.Dirt  = "dirt.png",
	.Stone = "stone.png",
	.Sand  = "sand.png",
	.Water = "water.png",
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

try_get_tile :: proc(world: World, x, y: int) -> (Tile, bool) {
	if x < 0 || x >= world.w || y < 0 || y >= world.h {
		return {}, false
	}
	return world.tiles[y * world.h + x], true
}

Undo :: struct {
	x, y:     int,
	old, new: Tile,
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

	rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_HIGHDPI})

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

	world: World
	if os2.exists(WORLD_PATH) {
		import_world(&world)
	} else {
		world = {
			w     = GRID_CELL_COUNT,
			h     = GRID_CELL_COUNT,
			tiles = make([]Tile, GRID_CELL_COUNT * GRID_CELL_COUNT),
		}
	}
	defer {
		delete(world.tiles)
	}

	selected_tile: Tile = .Grass
	hovered: [2]int

	show_grid := false
	show_debug_grid := false
	export_world_timer: f32 = -1
	import_world_timer: f32 = -1

	undo_stack: sa.Small_Array(UNDO_STEPS, Undo)
	undo_idx := -1

	for !rl.WindowShouldClose() {
		grid_start: rl.Vector2

		delta := rl.GetFrameTime()
		rw, rh := rl.GetRenderWidth(), rl.GetRenderHeight()

		{ 	// update

			if rl.IsKeyPressed(.G) {
				show_grid = !show_grid
			}
			if rl.IsKeyPressed(.D) {
				show_debug_grid = !show_debug_grid
			}

			if rl.IsKeyPressed(.C) {
				slice.fill(world.tiles, Tile.None)
			}

			if rl.IsKeyPressed(.Z) {
				if undo_idx >= 0 {
					undo := sa.get(undo_stack, undo_idx)
					world.tiles[undo.y * world.w + undo.x] = undo.old
					undo_idx -= 1
					fmt.printfln("Undid {} -> {} @ ({}, {})", undo.old, undo.new, undo.x, undo.y)
				}
			} else if rl.IsKeyPressed(.Y) {
				if undo_idx < sa.len(undo_stack) - 1 {
					undo_idx += 1
					redo := sa.get(undo_stack, undo_idx)
					world.tiles[redo.y * world.w + redo.x] = redo.new
					fmt.printfln("Redid {} -> {} @ ({}, {})", redo.old, redo.new, redo.x, redo.y)
				}
			}

			if rl.IsKeyPressed(.S) {
				export_world(world)
				export_world_timer = LOAD_SAVE_TIMER
				import_world_timer = -1
			} else if rl.IsKeyPressed(.L) {
				import_world(&world)
				import_world_timer = LOAD_SAVE_TIMER
				export_world_timer = -1
			}

			if rl.IsKeyPressed(.Q) && int(selected_tile) > int(Tile.None) + 1 {
				selected_tile = cast(Tile)(i32(selected_tile) - 1)
			} else if rl.IsKeyPressed(.E) && int(selected_tile) < len(Tile) - 1 {
				selected_tile = cast(Tile)(i32(selected_tile) + 1)
			}

			grid_start = {f32(rw - GRID_SIZE) / 2, f32(rh - GRID_SIZE) / 2}

			pos := rl.GetMousePosition()
			outer: for y in 0 ..< world.h {
				for x in 0 ..< world.w {
					if pos.x > grid_start.x + f32(x) * GRID_TILE_SIZE &&
					   pos.x < grid_start.x + f32(x + 1) * GRID_TILE_SIZE &&
					   pos.y > grid_start.y + f32(y) * GRID_TILE_SIZE &&
					   pos.y < grid_start.y + f32(y + 1) * GRID_TILE_SIZE {
						hovered = {x, y}

						if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
							tile := &world.tiles[y * world.h + x]

							old_tile := tile^
							if rl.IsMouseButtonDown(.LEFT) && tile^ != selected_tile {
								tile^ = selected_tile
								fmt.printfln("Updated ({}, {}) to {}", x, y, tile^)
							} else if rl.IsMouseButtonDown(.RIGHT) && tile^ != .None {
								tile^ = .None
								fmt.printfln("Updated ({}, {}) to {}", x, y, tile^)
							}
							new_tile := tile^

							if old_tile != new_tile {
								undo := Undo {
									x   = x,
									y   = y,
									old = old_tile,
									new = new_tile,
								}
								if undo_idx == sa.cap(undo_stack) - 1 {
									// Full
									sa.ordered_remove(&undo_stack, 0)
									sa.append(&undo_stack, undo)
								} else if undo_idx < sa.len(undo_stack) - 1 {
									// Overwrite
									sa.resize(&undo_stack, undo_idx + 1)
									sa.append(&undo_stack, undo)
									undo_idx += 1
								} else {
									// Normal
									undo_idx = sa.len(undo_stack)
									sa.append(&undo_stack, undo)
								}
							}

							break outer
						}
					}
				}
			}
		}

		{ 	// render
			rl.BeginDrawing()
			rl.ClearBackground({16, 16, 16, 255})

			DrawTextLayout(
				16,
				16,
				{fmt.ctprintf("Tile: {}", selected_tile), rl.RAYWHITE},
				{fmt.ctprintf("Grid: {} / {}", show_grid, show_debug_grid), rl.RAYWHITE},
				{
					fmt.ctprintf(
						"Hovered: {} ({})",
						hovered,
						world.tiles[hovered.y * world.h + hovered.x],
					),
					rl.RAYWHITE,
				},
			)

			DrawTextLayout(
				16,
				rh - 16,
				{fmt.ctprintf("G/D : Display (Debug) Grid"), rl.RAYWHITE},
				{fmt.ctprintf("Q/E : Prev/Next Tile"), rl.RAYWHITE},
				{fmt.ctprintf("S/L : Save/Load World"), rl.RAYWHITE},
				{fmt.ctprintf("Z/Y : Undo/Redo"), rl.RAYWHITE},
				dir = .Bottom_Up,
			)

			if export_world_timer > 0 {
				if export_world_timer < LOAD_SAVE_TIMER_FADE {
					rl.DrawText(
						"Exported World",
						16,
						16 + 24 + 24 + 24,
						24,
						rl.ColorAlpha(rl.RAYWHITE, export_world_timer / LOAD_SAVE_TIMER_FADE),
					)
				} else {
					rl.DrawText("Exported World", 16, 16 + 24 + 24 + 24, 24, rl.RAYWHITE)
				}
				export_world_timer -= delta
			} else if import_world_timer > 0 {
				if import_world_timer < LOAD_SAVE_TIMER_FADE {
					rl.DrawText(
						"Imported World",
						16,
						16 + 24 + 24 + 24,
						24,
						rl.ColorAlpha(rl.RAYWHITE, import_world_timer / LOAD_SAVE_TIMER_FADE),
					)
				} else {
					rl.DrawText("Imported World", 16, 16 + 24 + 24 + 24, 24, rl.RAYWHITE)
				}
				import_world_timer -= delta
			}

			for world_y in 0 ..< world.h {
				for world_x in 0 ..< world.w {
					tile, tile_ok := try_get_tile(world, world_x, world_y)
					assert(tile_ok)
					if tile == .None {
						continue
					}

					for display_dy in 0 ..< 2 {
						for display_dx in 0 ..< 2 {
							display_x := world_x + display_dx
							display_y := world_y + display_dy

							tile_bits: [Tile]Five_Tile_Bits

							tile_br, tile_br_ok := try_get_tile(
								world,
								display_x - 0,
								display_y - 0,
							)
							tile_tr, tile_tr_ok := try_get_tile(
								world,
								display_x - 0,
								display_y - 1,
							)
							tile_bl, tile_bl_ok := try_get_tile(
								world,
								display_x - 1,
								display_y - 0,
							)
							tile_tl, tile_tl_ok := try_get_tile(
								world,
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
									grid_start.x + f32(display_x) * GRID_TILE_SIZE,
									grid_start.y + f32(display_y) * GRID_TILE_SIZE,
									GRID_TILE_SIZE,
									GRID_TILE_SIZE,
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
				}
			}

			if show_grid {
				for x in 0 ..= world.h {
					// Vertical
					rl.DrawLineV(
						grid_start + {0, f32(x) * GRID_TILE_SIZE},
						grid_start + {f32(world.h) * GRID_TILE_SIZE, f32(x) * GRID_TILE_SIZE},
						rl.GREEN,
					)
				}

				for y in 0 ..= world.w {
					// Horizontal
					rl.DrawLineV(
						grid_start + {f32(y) * GRID_TILE_SIZE, 0},
						grid_start + {f32(y) * GRID_TILE_SIZE, f32(world.w) * GRID_TILE_SIZE},
						rl.GREEN,
					)
				}
			}

			if show_debug_grid {
				offset_colour := rl.ColorAlpha(rl.BLUE, 0.5)

				for x in 0 ..= (world.h + 1) {
					// Vertical
					rl.DrawLineV(
						grid_start - GRID_TILE_OFFSET + {0, f32(x) * GRID_TILE_SIZE},
						grid_start -
						GRID_TILE_OFFSET +
						{f32(world.h + 1) * GRID_TILE_SIZE, f32(x) * GRID_TILE_SIZE},
						offset_colour,
					)
				}

				for y in 0 ..= (world.w + 1) {
					// Horizontal
					rl.DrawLineV(
						grid_start - GRID_TILE_OFFSET + {f32(y) * GRID_TILE_SIZE, 0},
						grid_start -
						GRID_TILE_OFFSET +
						{f32(y) * GRID_TILE_SIZE, f32(world.w + 1) * GRID_TILE_SIZE},
						offset_colour,
					)
				}
			}

			// Selected indicator
			rl.DrawRectangleLines(
				i32(grid_start.x + f32(hovered.x) * GRID_TILE_SIZE),
				i32(grid_start.y + f32(hovered.y) * GRID_TILE_SIZE),
				GRID_TILE_SIZE,
				GRID_TILE_SIZE,
				rl.RAYWHITE,
			)


			rl.EndDrawing()

			when ODIN_DEBUG {
				for bad_free in tracking_allocator.bad_free_array {
					fmt.eprintfln("Bad free {} at {}\n", bad_free.memory, bad_free.location)
				}
				if len(tracking_allocator.bad_free_array) > 0 {
					os2.exit(1)
				}
				clear(&tracking_allocator.bad_free_array)
			}
			free_all(context.temp_allocator)
		}
	}
}

World :: struct {
	w:     int,
	h:     int,
	tiles: []Tile,
}

export_world :: proc(world: World) {
	if world.w == 0 || world.h == 0 {return}

	file, err := os2.open(WORLD_PATH, {.Write, .Create})
	if err != nil {
		fmt.eprintln("Could not save world:", err)
		return
	}
	defer os2.close(file)

	writer := os2.to_writer(file)

	cbor_err := cbor.marshal_into_writer(writer, world)
	if cbor_err != nil {
		fmt.eprintln("Could not save world:", cbor_err)
		return
	}

	fmt.printfln("Saved world {}x{}", world.w, world.h)
}

import_world :: proc(world: ^World) {
	file, err := os2.open(WORLD_PATH)
	if err != nil {
		fmt.eprintln("Could not load world:", err)
		return
	}
	defer os2.close(file)

	reader := os2.to_reader(file)

	new_world: World

	cbor_err := cbor.unmarshal_from_reader(reader, &new_world)
	if cbor_err != nil {
		fmt.eprintln("Could not load world:", cbor_err)
		return
	}

	if world != nil && world.w == new_world.w && world.h == new_world.h {
		if len(world.tiles) > 0 {
			delete(world.tiles)
		}
		world^ = new_world
	} else {
		defer delete(new_world.tiles)
		world.w = max(world.w, new_world.w)
		world.h = max(world.h, new_world.h)
		world.tiles = make([]Tile, world.w * world.h)
		min_w := min(world.w, new_world.w)
		min_h := min(world.h, new_world.h)
		for y in 0 ..< min_h {
			copy(world.tiles[y * min_h:][:min_w], new_world.tiles[y * min_h:][:min_w])
		}
	}

	fmt.printfln("Loaded world {}x{}", new_world.w, new_world.h)
}
