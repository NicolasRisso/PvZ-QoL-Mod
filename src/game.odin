package pvzspeed

import "core:fmt"
import win "core:sys/windows"

// A live connection to the running game process.
//
// This tool is a 64-bit process driving a 32-bit target. That is fine for the
// Win32 memory APIs, but every pointer we read OUT of the game is 32 bits, so
// they are read as u32 and widened. Reading them straight into a uintptr would
// pull in 4 bytes of neighbouring garbage.
Game :: struct {
	handle: win.HANDLE,
	pid:    u32,
	object: uintptr, // resolved app object; re-resolved each tick
}

Attach_Error :: enum {
	None,
	Not_Running,
	Launcher_Only, // DRM stub is up but the real game has not spawned yet
	Open_Failed,
	Bad_Build, // fingerprint mismatch - refuse to write
	No_Object, // app object not constructed yet (still on splash/loading)
}

find_pid :: proc(name: string) -> (pid: u32, ok: bool) {
	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE_VALUE {
		return 0, false
	}
	defer win.CloseHandle(snap)

	entry: win.PROCESSENTRY32W
	entry.dwSize = size_of(win.PROCESSENTRY32W)

	if !win.Process32FirstW(snap, &entry) {
		return 0, false
	}
	for {
		buf: [win.MAX_PATH]u8
		exe := win.wstring_to_utf8(buf[:], win.wstring(raw_data(entry.szExeFile[:])), -1)
		if exe == name {
			return entry.th32ProcessID, true
		}
		if !win.Process32NextW(snap, &entry) {
			break
		}
	}
	return 0, false
}

read_raw :: proc(g: ^Game, addr: uintptr, dst: []u8) -> bool {
	got: uint
	ok := win.ReadProcessMemory(g.handle, rawptr(addr), raw_data(dst), uint(len(dst)), &got)
	return bool(ok) && got == uint(len(dst))
}

write_raw :: proc(g: ^Game, addr: uintptr, src: []u8) -> bool {
	put: uint
	ok := win.WriteProcessMemory(g.handle, rawptr(addr), raw_data(src), uint(len(src)), &put)
	return bool(ok) && put == uint(len(src))
}

read_u32 :: proc(g: ^Game, addr: uintptr) -> (v: u32, ok: bool) {
	buf: [4]u8
	if !read_raw(g, addr, buf[:]) {
		return 0, false
	}
	return (^u32)(raw_data(buf[:]))^, true
}

read_i32 :: proc(g: ^Game, addr: uintptr) -> (v: i32, ok: bool) {
	buf: [4]u8
	if !read_raw(g, addr, buf[:]) {
		return 0, false
	}
	return (^i32)(raw_data(buf[:]))^, true
}

read_f64 :: proc(g: ^Game, addr: uintptr) -> (v: f64, ok: bool) {
	buf: [8]u8
	if !read_raw(g, addr, buf[:]) {
		return 0, false
	}
	return (^f64)(raw_data(buf[:]))^, true
}

write_f64 :: proc(g: ^Game, addr: uintptr, v: f64) -> bool {
	val := v
	return write_raw(g, addr, (cast([^]u8)&val)[:8])
}

// Verify we are attached to the build these offsets were derived from.
//
// This is the guard that keeps us from corrupting somebody else's game. A
// different build (GOG, the 1.0.0.1051 release, a localised repack) will have
// different field offsets, and blindly writing 8 bytes at object+0x4F0 there
// would land in an arbitrary member.
verify_build :: proc(g: ^Game) -> bool {
	expected := KNOWN_VTABLE_HEAD
	for want, i in expected {
		got, ok := read_u32(g, SEXYAPP_VTABLE + uintptr(i * 4))
		if !ok || got != want {
			return false
		}
	}
	return true
}

// Resolve the app object through the static global, then structurally validate
// it. The object lives on the heap so its address changes every run; the global
// that points at it does not.
resolve_object :: proc(g: ^Game) -> (obj: uintptr, ok: bool) {
	ptr, read_ok := read_u32(g, GLOBAL_APP_PTR)
	if !read_ok || ptr == 0 {
		return 0, false
	}
	candidate := uintptr(ptr)

	// obj[0] must be a vtable pointer, i.e. point into the image.
	vptr, vok := read_u32(g, candidate)
	if !vok || uintptr(vptr) < IMAGE_BASE || uintptr(vptr) >= IMAGE_BASE + IMAGE_SIZE {
		return 0, false
	}

	// Frame time is 10ms on a stock build. Cheap structural check that we are
	// looking at the pacing block and not some unrelated allocation.
	ft, fok := read_i32(g, candidate + OFF_FRAME_TIME)
	if !fok || ft != EXPECTED_FRAME_TIME {
		return 0, false
	}

	// Current multiplier should be a sane finite number.
	mult, mok := read_f64(g, candidate + OFF_MULTIPLIER)
	if !mok || mult <= 0.0 || mult > 1000.0 {
		return 0, false
	}

	return candidate, true
}

attach :: proc(g: ^Game) -> Attach_Error {
	pid, found := find_pid(PROCESS_NAME)
	if !found {
		if _, launcher := find_pid(LAUNCHER_NAME); launcher {
			return .Launcher_Only
		}
		return .Not_Running
	}

	if g.handle == nil || g.pid != pid {
		if g.handle != nil {
			win.CloseHandle(g.handle)
			g.handle = nil
		}
		access: u32 =
			win.PROCESS_VM_READ | win.PROCESS_VM_WRITE | win.PROCESS_VM_OPERATION | win.PROCESS_QUERY_INFORMATION
		h := win.OpenProcess(access, false, pid)
		if h == nil {
			return .Open_Failed
		}
		g.handle = h
		g.pid = pid
	}

	if !verify_build(g) {
		return .Bad_Build
	}

	obj, ok := resolve_object(g)
	if !ok {
		return .No_Object
	}
	g.object = obj
	return .None
}

detach :: proc(g: ^Game) {
	if g.handle != nil {
		win.CloseHandle(g.handle)
		g.handle = nil
	}
	g.pid = 0
	g.object = 0
}

set_speed :: proc(g: ^Game, speed: f64) -> bool {
	if g.object == 0 {
		return false
	}
	return write_f64(g, g.object + OFF_MULTIPLIER, speed)
}

get_speed :: proc(g: ^Game) -> (f64, bool) {
	if g.object == 0 {
		return 0, false
	}
	return read_f64(g, g.object + OFF_MULTIPLIER)
}

get_update_count :: proc(g: ^Game) -> (u32, bool) {
	if g.object == 0 {
		return 0, false
	}
	return read_u32(g, g.object + OFF_UPDATE_COUNT)
}

attach_error_message :: proc(e: Attach_Error) -> string {
	switch e {
	case .None:
		return "connected"
	case .Not_Running:
		return "waiting for Plants vs. Zombies..."
	case .Launcher_Only:
		return "launcher running, waiting for game to start..."
	case .Open_Failed:
		return "could not open process (try running as administrator)"
	case .Bad_Build:
		return "unrecognised game build - refusing to write"
	case .No_Object:
		return "game still loading..."
	}
	return "unknown"
}

_ :: fmt
