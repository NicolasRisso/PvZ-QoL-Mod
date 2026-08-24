package pvzspeed

import win "core:sys/windows"

// ---------------------------------------------------------------------------
// Number-key plant selection.
//
// Pressing 1-9 / 0 picks the corresponding seed packet.
//
// Why this works by moving the cursor rather than by posting messages:
// the game imports GetCursorPos + ScreenToClient and runs a plain PeekMessageA
// loop, with no DirectInput. It polls the real cursor position, so a synthetic
// WM_MOUSEMOVE with fake coordinates in lParam gets overridden by the next
// poll. Driving the actual cursor is the approach that matches how the game
// reads input.
//
// The cursor is parked back where it started immediately afterwards, so the
// visible effect is a single-frame blip.
// ---------------------------------------------------------------------------

// Seed packet geometry, in 800x600 client coordinates.
//
// CALIBRATE THESE against a real level before trusting them - see
// docs/FINDINGS.md. They are measured from the seed bank at the top-left of
// the board during a standard level.
SEED_FIRST_X :: 36 // centre x of packet 0
SEED_STRIDE_X :: 51 // spacing between packet centres
SEED_CENTER_Y :: 55 // centre y of the packet row

MAX_SEED_SLOTS :: 10

seed_geometry_calibrated :: proc() -> bool {
	// Flipped to true once the constants above have been measured in-game.
	// While false, the feature refuses to click rather than clicking blind.
	return SEED_CALIBRATED
}

SEED_CALIBRATED :: #config(SEED_CALIBRATED, false)

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
		return false // stop enumerating
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
	rect: win.RECT
	if !win.GetClientRect(ctx.hwnd, &rect) {
		return {}, false
	}
	return Window_Info{hwnd = ctx.hwnd, client_w = rect.right, client_h = rect.bottom}, true
}

// Only ever act when the game is the window actually receiving input.
//
// This matters much more here than for the speed hotkey. Cycling speed while
// alt-tabbed is harmless; warping the cursor and clicking while the user is in
// another application is not.
game_is_focused :: proc(info: Window_Info) -> bool {
	return win.GetForegroundWindow() == info.hwnd
}

// Client-space centre of packet `index`, scaled if the window is not native
// 800x600.
packet_point :: proc(info: Window_Info, index: int) -> (x: i32, y: i32) {
	sx := f64(info.client_w) / 800.0
	sy := f64(info.client_h) / 600.0
	cx := f64(SEED_FIRST_X + i32(index) * SEED_STRIDE_X) * sx
	cy := f64(SEED_CENTER_Y) * sy
	return i32(cx), i32(cy)
}

@(private = "file")
send_click :: proc() {
	inputs: [2]win.INPUT
	inputs[0].type = .MOUSE
	inputs[0].mi.dwFlags = win.MOUSEEVENTF_LEFTDOWN
	inputs[1].type = .MOUSE
	inputs[1].mi.dwFlags = win.MOUSEEVENTF_LEFTUP
	win.SendInput(2, raw_data(inputs[:]), size_of(win.INPUT))
}

// Click seed packet `index` (0-based), restoring the cursor afterwards.
select_plant :: proc(info: Window_Info, index: int) -> bool {
	if index < 0 || index >= MAX_SEED_SLOTS {
		return false
	}
	if !game_is_focused(info) {
		return false
	}
	if !seed_geometry_calibrated() {
		return false
	}

	saved: win.POINT
	have_saved := bool(win.GetCursorPos(&saved))

	cx, cy := packet_point(info, index)
	pt := win.POINT{cx, cy}
	if !win.ClientToScreen(info.hwnd, &pt) {
		return false
	}

	win.SetCursorPos(pt.x, pt.y)
	send_click()

	if have_saved {
		win.SetCursorPos(saved.x, saved.y)
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
