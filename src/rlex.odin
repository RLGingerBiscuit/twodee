package twodee

import rl "vendor:raylib"
TextParams :: struct {
	text:   cstring,
	colour: rl.Color,
}

LayoutDirection :: enum {
	Top_Down,
	Bottom_Up,
}

DrawTextLayout :: proc(
	start_x, start_y: i32,
	texts: ..TextParams,
	size: i32 = 24,
	padding: i32 = 2,
	dir: LayoutDirection = .Top_Down,
) {
	x, y := start_x, start_y
	if dir == .Bottom_Up {
		y -= size - padding
	}

	for text in texts {
		rl.DrawText(text.text, x, y, size, text.colour)

		switch dir {
		case .Top_Down:
			y += size + padding
		case .Bottom_Up:
			y -= size + padding
		}
	}
}
