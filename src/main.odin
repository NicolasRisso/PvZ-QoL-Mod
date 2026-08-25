package pvzspeed

import "core:fmt"
import "core:strings"
import win "core:sys/windows"
import "core:time"
import rl "vendor:raylib"

// Speed presets cycled by SPACE. The last one is user-editable.
Step :: struct {
	label: cstring,
	speed: f64,
}

State :: struct {
	steps:        [4]Step,
	index:        int,
	custom:       f64,
	game:         Game,
	status:       string,
	connected:    bool,
	measured:     f64,
	last_count:   u32,
	last_tick:    time.Tick,
	window:       Window_Info,
	have_window:  bool,
	last_slot:    int,
	last_slot_ok: bool,
	slot_flash:   f32, // fades out after a plant key is pressed
}

WIN_W :: 360
WIN_H :: 452

// Palette - loosely PvZ-ish without imitating any game art.
COL_BG :: rl.Color{24, 28, 24, 255}
COL_PANEL :: rl.Color{34, 40, 34, 255}
COL_ACCENT :: rl.Color{124, 194, 66, 255}
COL_ACCENT_DIM :: rl.Color{70, 110, 40, 255}
COL_TEXT :: rl.Color{226, 232, 222, 255}
COL_MUTED :: rl.Color{130, 142, 128, 255}
COL_WARN :: rl.Color{226, 178, 64, 255}
COL_BAD :: rl.Color{214, 96, 84, 255}

current_step :: proc(s: ^State) -> Step {
	st := s.steps[s.index]
	if s.index == len(s.steps) - 1 {
		st.speed = s.custom
	}
	return st
}

apply_current :: proc(s: ^State) {
	if !s.connected {
		return
	}
	set_speed(&s.game, current_step(s).speed)
}

// Read the game's own update counter so the readout reflects what the game is
// actually doing, not merely what we asked for.
update_measurement :: proc(s: ^State) {
	if !s.connected {
		s.measured = 0
		s.last_count = 0
		return
	}
	count, ok := get_update_count(&s.game)
	if !ok {
		return
	}
	now := time.tick_now()
	if s.last_count != 0 {
		elapsed := time.duration_seconds(time.tick_diff(s.last_tick, now))
		if elapsed >= 0.4 {
			s.measured = f64(count - s.last_count) / elapsed
			s.last_count = count
			s.last_tick = now
		}
	} else {
		s.last_count = count
		s.last_tick = now
	}
}

Key_Watch :: struct {
	was_down: map[i32]bool,
}

// Edge-triggered, polled globally so the hotkeys work while the game has focus.
pressed :: proc(kw: ^Key_Watch, vk: i32) -> bool {
	down := (u16(win.GetAsyncKeyState(vk)) & 0x8000) != 0
	prev := kw.was_down[vk]
	kw.was_down[vk] = down
	return down && !prev
}

// SPACE must not fire while the user is typing into our own custom-speed box,
// otherwise it would cycle the preset out from under them.
typing_in_gui :: proc(edit_mode: bool) -> bool {
	return edit_mode && rl.IsWindowFocused()
}

draw_ui :: proc(s: ^State, custom_box: ^i32, edit_mode: ^bool) {
	rl.ClearBackground(COL_BG)

	// --- header ---
	rl.DrawRectangle(0, 0, WIN_W, 42, COL_PANEL)
	rl.DrawText("PvZ Speed Mod", 14, 13, 20, COL_ACCENT)

	// --- connection status ---
	y: i32 = 52
	if s.connected {
		rl.DrawCircle(22, y + 8, 5, COL_ACCENT)
		txt := fmt.ctprintf("connected  -  pid %d", s.game.pid)
		rl.DrawText(txt, 36, y, 14, COL_TEXT)
	} else {
		rl.DrawCircle(22, y + 8, 5, COL_WARN)
		rl.DrawText(strings.clone_to_cstring(s.status, context.temp_allocator), 36, y, 14, COL_WARN)
	}

	// --- speed presets ---
	y = 84
	rl.DrawText("SPEED", 14, y, 12, COL_MUTED)
	y += 20

	bw: f32 = (WIN_W - 28 - 3 * 6) / 4
	for st, i in s.steps {
		x := f32(14) + f32(i) * (bw + 6)
		rect := rl.Rectangle{x, f32(y), bw, 38}
		active := i == s.index

		rl.DrawRectangleRec(rect, active ? COL_ACCENT : COL_PANEL)
		rl.DrawRectangleLinesEx(rect, 1, active ? COL_ACCENT : COL_ACCENT_DIM)

		label := st.label
		if i == len(s.steps) - 1 {
			label = fmt.ctprintf("%.4gx", s.custom)
		}
		tw := rl.MeasureText(label, 16)
		rl.DrawText(
			label,
			i32(x + (bw - f32(tw)) / 2),
			y + 11,
			16,
			active ? COL_BG : COL_TEXT,
		)

		// Clicking a preset selects it too - the panel is not just a readout.
		if rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) &&
		   rl.IsMouseButtonPressed(.LEFT) {
			s.index = i
			apply_current(s)
		}
	}

	// --- custom value ---
	y += 48
	rl.DrawText("custom", 14, y + 6, 13, COL_MUTED)
	box := rl.Rectangle{72, f32(y), 76, 26}
	if rl.GuiValueBox(box, "", custom_box, 1, 100, edit_mode^) != 0 {
		edit_mode^ = !edit_mode^
	}
	if f64(custom_box^) != s.custom {
		s.custom = f64(custom_box^)
		if s.index == len(s.steps) - 1 {
			apply_current(s)
		}
	}
	rl.DrawText("x   (1 - 100)", 156, y + 6, 13, COL_MUTED)

	// --- measured rate ---
	y += 44
	rl.DrawText("MEASURED", 14, y, 12, COL_MUTED)
	y += 20
	if s.connected && s.measured > 0 {
		ratio := s.measured / BASE_UPDATE_RATE
		rl.DrawText(fmt.ctprintf("%.2fx", ratio), 14, y, 28, COL_ACCENT)
		rl.DrawText(fmt.ctprintf("%.0f updates/sec", s.measured), 108, y + 10, 14, COL_MUTED)

		// Bar scaled so 1x sits at a quarter width; caps at 4x.
		bar := rl.Rectangle{14, f32(y + 40), WIN_W - 28, 8}
		rl.DrawRectangleRec(bar, COL_PANEL)
		frac := clamp(f32(ratio) / 4.0, 0, 1)
		rl.DrawRectangleRec(
			rl.Rectangle{bar.x, bar.y, bar.width * frac, bar.height},
			COL_ACCENT,
		)
	} else {
		rl.DrawText("--", 14, y, 28, COL_MUTED)
	}

	// --- plant selection ---
	y += 68
	rl.DrawLine(14, y, WIN_W - 14, y, COL_PANEL)
	y += 12
	rl.DrawText("PLANTS", 14, y, 12, COL_MUTED)
	y += 20

	if !SEED_CALIBRATED {
		rl.DrawText("number keys disabled", 14, y, 14, COL_WARN)
		rl.DrawText("seed positions not calibrated yet", 14, y + 18, 12, COL_MUTED)
	} else if !s.have_window {
		rl.DrawText("no game window", 14, y, 14, COL_WARN)
	} else {
		rl.DrawText("press 1-9, 0 in game", 14, y, 14, COL_TEXT)
		// Slot pips, flashing the one most recently pressed.
		for i in 0 ..< MAX_SEED_SLOTS {
			px := f32(14 + i * 33)
			r := rl.Rectangle{px, f32(y + 22), 28, 22}
			hot := s.last_slot_ok && s.last_slot == i && s.slot_flash > 0
			col := hot ? COL_ACCENT : COL_PANEL
			rl.DrawRectangleRec(r, col)
			label := fmt.ctprintf("%d", i == 9 ? 0 : i + 1)
			tw := rl.MeasureText(label, 13)
			rl.DrawText(label, i32(px + (28 - f32(tw)) / 2), y + 27, 13, hot ? COL_BG : COL_MUTED)
		}
	}

	// --- footer ---
	fy: i32 = WIN_H - 46
	rl.DrawLine(14, fy - 10, WIN_W - 14, fy - 10, COL_PANEL)
	rl.DrawText("SPACE cycle speed    1-9,0 pick plant", 14, fy, 12, COL_MUTED)
	rl.DrawText("hotkeys work while the game is focused", 14, fy + 16, 12, COL_MUTED)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_TOPMOST, .VSYNC_HINT})
	rl.InitWindow(WIN_W, WIN_H, "PvZ Speed Mod")
	// NOTE: deliberately no rl.CloseWindow().
	//
	// raylib and user32 both export a symbol named CloseWindow. We link with
	// /FORCE:MULTIPLE (raylib + Win32 in one binary is otherwise a duplicate
	// symbol error), and the linker keeps user32's version - so calling
	// rl.CloseWindow() here would invoke the Win32 CloseWindow(HWND) with no
	// argument. The OS reclaims the window on exit anyway.
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // Esc must not close the window; it is a game key

	rl.GuiLoadStyleDefault()

	s: State
	s.steps = [4]Step{{"1x", 1.0}, {"2x", 2.0}, {"3x", 3.0}, {"Custom", 5.0}}
	s.custom = 5.0
	s.status = "waiting for Plants vs. Zombies..."

	custom_box: i32 = 5
	edit_mode := false

	kw: Key_Watch
	kw.was_down = make(map[i32]bool)
	defer delete(kw.was_down)

	reattach_at := time.tick_now()

	for !rl.WindowShouldClose() {
		// (Re)attach on a timer so the tool survives the game restarting.
		if !s.connected &&
		   time.duration_seconds(time.tick_diff(reattach_at, time.tick_now())) >= 0 {
			err := attach(&s.game)
			s.status = attach_error_message(err)
			s.connected = err == .None
			if s.connected {
				s.last_count = 0
				apply_current(&s)
				s.window, s.have_window = find_game_window(s.game.pid)
			}
			reattach_at = time.tick_add(time.tick_now(), 1 * time.Second)
		}

		if !typing_in_gui(edit_mode) {
			if pressed(&kw, win.VK_SPACE) {
				s.index = (s.index + 1) % len(s.steps)
				apply_current(&s)
			}
			if s.have_window {
				for vk in i32('0') ..= i32('9') {
					if pressed(&kw, vk) {
						if slot, ok := vk_to_slot(vk); ok {
							s.last_slot_ok = select_plant(s.window, slot)
							s.last_slot = slot
							if s.last_slot_ok {
								s.slot_flash = 0.35
							}
						}
					}
				}
			}
		}

		if s.slot_flash > 0 {
			s.slot_flash -= rl.GetFrameTime()
		}

		// Detect the game going away.
		if s.connected {
			if _, ok := get_speed(&s.game); !ok {
				detach(&s.game)
				s.connected = false
				s.have_window = false
				s.status = "lost connection, waiting..."
			}
		}

		update_measurement(&s)

		rl.BeginDrawing()
		draw_ui(&s, &custom_box, &edit_mode)
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

	// Leave the game at normal speed on the way out.
	if s.connected {
		set_speed(&s.game, 1.0)
	}
	detach(&s.game)
}
