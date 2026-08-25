package pvzspeed

// CoinType values that represent ordinary money or sun. Awards, seed packets,
// presents, chocolate, and tools deliberately remain manual.
collectible_type :: proc(kind: i32) -> bool {
	return kind >= 1 && kind <= 6
}

// Resolve and validate the active Board.
resolve_board :: proc(g: ^Game) -> (board: uintptr, ok: bool) {
	if g.object == 0 {
		return 0, false
	}
	ptr, pok := read_u32(g, g.object + OFF_BOARD)
	if !pok || ptr == 0 {
		return 0, false
	}
	board = uintptr(ptr)

	vtable, vok := read_u32(g, board)
	owner, ook := read_u32(g, board + OFF_BOARD_APP)
	if !vok || !ook ||
	   uintptr(vtable) < IMAGE_BASE || uintptr(vtable) >= IMAGE_BASE + IMAGE_SIZE ||
	   uintptr(owner) != g.object {
		return 0, false
	}

	return board, true
}

// Require an empty hand before returning the active Board.
collect_board :: proc(g: ^Game) -> (board: uintptr, ok: bool) {
	board, ok = resolve_board(g)
	if !ok {
		return 0, false
	}
	cursor_ptr, cok := read_u32(g, board + OFF_BOARD_CURSOR)
	if !cok || cursor_ptr == 0 {
		return 0, false
	}
	cursor_type, tok := read_i32(g, uintptr(cursor_ptr) + OFF_CURSOR_TYPE)
	if !tok || cursor_type != CURSOR_TYPE_NORMAL {
		return 0, false
	}
	return board, true
}

// Collect every currently hittable sun/coin. Returns the number of clicks
// posted. Each entry is rechecked immediately before its click so a user
// picking up a packet or shovel stops collection on the same polling pass.
auto_collect_tick :: proc(g: ^Game, info: ^Window_Info) -> int {
	board, ok := collect_board(g)
	if !ok || !game_is_focused(info^) {
		return 0
	}

	data_ptr, dok := read_u32(g, board + OFF_BOARD_COINS)
	max_used, mok := read_u32(g, board + OFF_BOARD_COIN_MAX_USED)
	if !dok || !mok || data_ptr == 0 || max_used > MAX_COIN_ENTRIES {
		return 0
	}

	clicked := 0
	for i in 0 ..< int(max_used) {
		entry := uintptr(data_ptr) + uintptr(i) * COIN_STRIDE
		dead, dead_ok := read_u8(g, entry + OFF_COIN_DEAD)
		collecting, collecting_ok := read_u8(g, entry + OFF_COIN_COLLECTING)
		kind, kind_ok := read_i32(g, entry + OFF_COIN_TYPE)
		if !dead_ok || !collecting_ok || !kind_ok || dead != 0 || collecting != 0 ||
		   !collectible_type(kind) {
			continue
		}

		x, xok := read_f32(g, entry + OFF_COIN_X)
		y, yok := read_f32(g, entry + OFF_COIN_Y)
		width, wok := read_i32(g, entry + OFF_OBJECT_WIDTH)
		height, hok := read_i32(g, entry + OFF_OBJECT_HEIGHT)
		if !xok || !yok || !wok || !hok || width <= 0 || width > 200 || height <= 0 || height > 200 {
			continue
		}

		// The stored position is the object's top-left; hit the middle of its
		// 60x60-ish GameObject rectangle. Off-screen spawns wait until visible.
		cx := x + f32(width) * 0.5
		cy := y + f32(height) * 0.5
		if cx < 0 || cx >= f32(DESIGN_W) || cy < 0 || cy >= f32(DESIGN_H) {
			continue
		}

		// Close the user-input race between the array read and message posting.
		if _, still_empty := collect_board(g); !still_empty {
			break
		}
		if click_design_point(info, cx, cy) {
			clicked += 1
		}
	}
	return clicked
}
