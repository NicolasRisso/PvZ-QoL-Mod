package pvzspeed

import win "core:sys/windows"

// ---------------------------------------------------------------------------
// Number-key plant selection.
//
// Pressing 1-9 / 0 picks the corresponding seed packet.
//
// The physical cursor is never moved. We post WM_MOUSEMOVE + WM_LBUTTONDOWN +
// WM_LBUTTONUP straight to the game's window handle, then post a final move
// back to wherever the real cursor is, so the game's own idea of the mouse
// (which it keeps at app+0x1608) ends up exactly where it started.
//
// Posting to a specific HWND is also what makes this safe: the messages are
// addressed to the game window, so nothing else on the desktop can receive
// them regardless of which window happens to be on top or focused.
//
// This was verified against a live game: posting a click at a computed packet
// centre changes that packet and no other (measured by pixel diff per slot).
// ---------------------------------------------------------------------------

// Seed packet geometry, measured in 800x600 client coordinates against PvZ
// GOTY 1.2.0.1096, level 1-7, standard 6-packet seed bank.
//
// Measured card extents (see docs/FINDINGS.md):
//   slot 1  x  96..142      slot 4  x 273..319
//   slot 2  x 155..201      slot 5  x 332..378
//   slot 3  x 214..260      slot 6  x 391..437
//
// Cards are ~47 wide on a 59 pixel pitch; the gap between cards belongs to the
// preceding slot as far as hit-testing is concerned, so aiming at the centre
// is comfortably inside.
SEED_FIRST_CENTER_X :: 119.0
SEED_STRIDE_X :: 59.0
SEED_CENTER_Y :: 42.0

// The layout above is authored for this logical size; everything scales from it.
DESIGN_W :: 800.0
DESIGN_H :: 600.0

MAX_SEED_SLOTS :: 10

Window_Info :: struct {
	hwnd:     win.HWND,
	client_w: i32,
	client_h: i32,
}

@(private = "file")
Find_Ctx :: struct {
	pid:  u32,
	hwnd: win.HWND,
}

@(private = "file")
enum_proc :: proc "system" (hwnd: win.HWND, lparam: win.LPARAM) -> win.BOOL {
	ctx := (^Find_Ctx)(uintptr(lparam))
	pid: u32
	win.GetWindowThreadProcessId(hwnd, &pid)
	if pid == ctx.pid && win.IsWindowVisible(hwnd) {
		ctx.hwnd = hwnd
		return false
	}
	return true
}

find_game_window :: proc(pid: u32) -> (info: Window_Info, ok: bool) {
	ctx := Find_Ctx {
		pid = pid,
	}
	win.EnumWindows(enum_proc, win.LPARAM(uintptr(&ctx)))
	if ctx.hwnd == nil {
		return {}, false
	}
	return refresh_window(ctx.hwnd)
}

// Client size is re-read every time we click, so resizing or going fullscreen
// mid-session is picked up without reattaching.
refresh_window :: proc(hwnd: win.HWND) -> (info: Window_Info, ok: bool) {
	rect: win.RECT
	if !win.GetClientRect(hwnd, &rect) || rect.right <= 0 || rect.bottom <= 0 {
		return {}, false
	}
	return Window_Info{hwnd = hwnd, client_w = rect.right, client_h = rect.bottom}, true
}

// Only act when the game is the window the user is actually looking at.
//
// Posting to the HWND cannot disturb another application, but this still
// matters: without it, typing "3" into a browser would silently swap the plant
// selection in the background game.
game_is_focused :: proc(info: Window_Info) -> bool {
	return win.GetForegroundWindow() == info.hwnd
}

// Centre of packet `index` in client pixels, scaled to the current client size.
//
// PvZ renders a fixed 800x600 layout stretched to the client area, so a plain
// proportional scale is correct. Both axes are scaled independently, which
// matches a stretch; if a build were ever letterboxed instead this would need
// a single uniform scale plus offset.
packet_point :: proc(info: Window_Info, index: int) -> (x: i32, y: i32) {
	sx := f64(info.client_w) / DESIGN_W
	sy := f64(info.client_h) / DESIGN_H
	cx := (SEED_FIRST_CENTER_X + f64(index) * SEED_STRIDE_X) * sx
	cy := SEED_CENTER_Y * sy
	return i32(cx + 0.5), i32(cy + 0.5)
}

@(private = "file")
make_lparam :: proc(x, y: i32) -> win.LPARAM {
	return win.LPARAM((u32(y) << 16) | (u32(x) & 0xFFFF))
}

@(private = "file")
post_at :: proc(hwnd: win.HWND, msg: u32, wparam: win.WPARAM, x, y: i32) {
	win.PostMessageW(hwnd, msg, wparam, make_lparam(x, y))
}

// Where the real cursor is, in the game's client coordinates. Used to restore
// the game's internal mouse position after the synthetic click.
@(private = "file")
cursor_in_client :: proc(hwnd: win.HWND) -> (p: win.POINT, ok: bool) {
	pt: win.POINT
	if !win.GetCursorPos(&pt) {
		return {}, false
	}
	if !win.ScreenToClient(hwnd, &pt) {
		return {}, false
	}
	return pt, true
}

MK_LBUTTON :: 0x0001

// Select seed packet `index` (0-based) without moving the physical cursor.
select_plant :: proc(info: ^Window_Info, index: int) -> bool {
	if index < 0 || index >= MAX_SEED_SLOTS {
		return false
	}
	if !game_is_focused(info^) {
		return false
	}

	// Pick up any resize / fullscreen change since we attached.
	if updated, ok := refresh_window(info.hwnd); ok {
		info^ = updated
	}

	cx, cy := packet_point(info^, index)
	restore, have_restore := cursor_in_client(info.hwnd)

	post_at(info.hwnd, win.WM_MOUSEMOVE, 0, cx, cy)
	post_at(info.hwnd, win.WM_LBUTTONDOWN, MK_LBUTTON, cx, cy)
	post_at(info.hwnd, win.WM_LBUTTONUP, 0, cx, cy)

	// Put the game's notion of the mouse back where the user's cursor really is,
	// so the selected plant follows their actual pointer rather than sticking to
	// the seed bank.
	if have_restore {
		post_at(info.hwnd, win.WM_MOUSEMOVE, 0, restore.x, restore.y)
	}
	return true
}

// Map a virtual-key code to a seed slot index. 1-9 -> 0-8, 0 -> 9.
vk_to_slot :: proc(vk: i32) -> (slot: int, ok: bool) {
	switch vk {
	case '1' ..= '9':
		return int(vk - '1'), true
	case '0':
		return 9, true
	}
	return 0, false
}
