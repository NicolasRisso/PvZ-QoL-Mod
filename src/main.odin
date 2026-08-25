package pvzspeed

import "core:fmt"
import "core:strings"
import win "core:sys/windows"
import "core:time"
import rl "vendor:raylib"

// Speed presets cycled by ALT. The last one is user-editable.
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
	plant_count:  i32, // read from the live SeedBank; locates the shovel
	have_seed_count: bool,
	shovel_flash: f32,
	auto_collect: bool,
	collect_flash: f32,
	next_collect: time.Tick,
}

WIN_W :: 360
WIN_H :: 566

// Packet selection is posted asynchronously. Give PvZ time to consume that
// click and update CursorObject before auto-collect trusts the memory gate.
COLLECT_INPUT_GRACE :: 350 * time.Millisecond

// Palette - loosely PvZ-ish without imitating any game art.
COL_BG :: rl.Color{24, 28, 24, 255}
COL_PANEL :: rl.Color{34, 40, 34, 255}
COL_ACCENT :: rl.Color{124, 194, 66, 255}
COL_ACCENT_DIM :: rl.Color{70, 110, 40, 255}
COL_TEXT :: rl.Color{226, 232, 222, 255}
COL_MUTED :: rl.Color{130, 142, 128, 255}
COL_WARN :: rl.Color{226, 178, 64, 255}
COL_BAD :: rl.Color{214, 96, 84, 255}

PROJECT_URL :: "https://github.com/NicolasRisso/PvZ-QoL-Mod"

// Roboto is embedded into the executable so the UI has consistent typography
// without shipping a sidecar font file. See assets/OFL-Roboto.txt.
ROBOTO_DATA :: #load("../assets/Roboto.ttf")
ui_font: rl.Font

draw_text :: proc(text: cstring, x, y, font_size: i32, color: rl.Color) {
	rl.DrawTextEx(ui_font, text, rl.Vector2{f32(x), f32(y)}, f32(font_size), 0.25, color)
}

measure_text :: proc(text: cstring, font_size: i32) -> i32 {
	size := rl.MeasureTextEx(ui_font, text, f32(font_size), 0.25)
	return i32(size.x + 0.5)
}

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
	primed:   bool, // first poll only records state, it must not fire
}

// ALT needs more care than a plain edge trigger, for two reasons:
//
//  1. GLFW synthesises an ALT keypress when it focuses its own window - that is
//     the documented Windows trick for getting around SetForegroundWindow
//     restrictions. A naive global poll sees it as a real tap, so merely
//     clicking this panel would cycle the game speed.
//  2. Alt+Tab would otherwise cycle the speed on the way out of the game.
//
// So: fire on ALT *release*, only if no other key was pressed during the hold,
// and only while the game itself is the foreground window. The synthetic press
// happens while our window is taking focus, so the game is not foreground and
// it is ignored.
Alt_Watch :: struct {
	down:           bool,
	dirty:          bool, // another key went down during this hold
	reverse:        bool, // Shift was held at any point during this Alt tap
	primed:         bool,
	was_focused:  bool,
	settle_frames: int, // frames left to ignore ALT entirely
}

// GLFW synthesises an ALT press whenever it focuses its own window (the Windows
// SetForegroundWindow workaround). It lands a frame or two after the loop
// starts, so priming alone does not catch it. Whenever our panel gains focus,
// blank out ALT briefly - a real user tap that close to a focus change is not
// something worth honouring anyway.
alt_note_focus :: proc(aw: ^Alt_Watch, focused_now: bool) {
	if focused_now && !aw.was_focused {
		aw.settle_frames = max(aw.settle_frames, 48)
	}
	aw.was_focused = focused_now
}

alt_cycle_direction :: proc(aw: ^Alt_Watch, game_focused: bool) -> int {
	down := (u16(win.GetAsyncKeyState(win.VK_MENU)) & 0x8000) != 0
	shift_down := (u16(win.GetAsyncKeyState(win.VK_SHIFT)) & 0x8000) != 0
	defer aw.down = down

	if !aw.primed {
		aw.primed = true
		// A hold already in progress at startup is by definition not the user's.
		aw.dirty = true
		return 0
	}
	if aw.settle_frames > 0 {
		aw.settle_frames -= 1
		aw.dirty = true // whatever happens during the blackout is not a tap
		return 0
	}
	if down && !aw.down {
		aw.dirty = false // start of a fresh hold
		aw.reverse = shift_down
		return 0
	}
	if down {
		aw.reverse = aw.reverse || shift_down
		// Any companion key (Tab being the one that matters) disqualifies it.
		if (u16(win.GetAsyncKeyState(win.VK_TAB)) & 0x8000) != 0 {
			aw.dirty = true
		}
		return 0
	}
	if !down && aw.down {
		if !aw.dirty && game_focused {
			return aw.reverse ? -1 : 1
		}
	}
	return 0
}

// Edge-triggered, polled globally so the hotkeys work while the game has focus.
//
// `primed` matters more than it looks: without it the very first poll sees an
// empty map, so prev is false, and any key already held down at launch fires
// instantly. Launching the tool with Alt+Tab would cycle the speed before the
// user touched anything.
pressed :: proc(kw: ^Key_Watch, vk: i32) -> bool {
	down := (u16(win.GetAsyncKeyState(vk)) & 0x8000) != 0
	prev, seen := kw.was_down[vk]
	kw.was_down[vk] = down
	if !seen || !kw.primed {
		return false
	}
	return down && !prev
}

// Hotkeys must not fire while the user is typing into our own custom-speed box,
// otherwise ALT/digits would act on the game instead of the text field.
typing_in_gui :: proc(edit_mode: bool) -> bool {
	return edit_mode && rl.IsWindowFocused()
}

draw_ui :: proc(s: ^State, custom_box: ^i32, edit_mode: ^bool) {
	rl.ClearBackground(COL_BG)

	// --- header ---
	rl.DrawRectangle(0, 0, WIN_W, 42, COL_PANEL)
	draw_text("PvZ QoL Mod", 14, 13, 20, COL_ACCENT)
	author: cstring = "by: Nicolas Risso"
	author_w := measure_text(author, 12)
	author_x := WIN_W - 14 - author_w
	author_rect := rl.Rectangle{f32(author_x - 3), 10, f32(author_w + 6), 22}
	author_hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), author_rect)
	draw_text(author, author_x, 16, 12, author_hover ? COL_TEXT : COL_MUTED)
	if author_hover && rl.IsMouseButtonPressed(.LEFT) {
		rl.OpenURL(PROJECT_URL)
	}

	// --- connection status ---
	y: i32 = 52
	if s.connected {
		rl.DrawCircle(22, y + 8, 5, COL_ACCENT)
		txt := fmt.ctprintf("connected  -  pid %d", s.game.pid)
		draw_text(txt, 36, y, 14, COL_TEXT)
	} else {
		rl.DrawCircle(22, y + 8, 5, COL_WARN)
		draw_text(strings.clone_to_cstring(s.status, context.temp_allocator), 36, y, 14, COL_WARN)
	}

	// --- speed presets ---
	y = 84
	draw_text("SPEED", 14, y, 12, COL_MUTED)
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
		tw := measure_text(label, 16)
		draw_text(
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
	draw_text("custom", 14, y + 6, 13, COL_MUTED)
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
	draw_text("x   (1 - 100)", 156, y + 6, 13, COL_MUTED)

	// --- measured rate ---
	y += 44
	draw_text("MEASURED", 14, y, 12, COL_MUTED)
	y += 20
	if s.connected && s.measured > 0 {
		ratio := s.measured / BASE_UPDATE_RATE
		draw_text(fmt.ctprintf("%.2fx", ratio), 14, y, 28, COL_ACCENT)
		draw_text(fmt.ctprintf("%.0f updates/sec", s.measured), 108, y + 10, 14, COL_MUTED)

		// Bar scaled so 1x sits at a quarter width; caps at 4x.
		bar := rl.Rectangle{14, f32(y + 40), WIN_W - 28, 8}
		rl.DrawRectangleRec(bar, COL_PANEL)
		frac := clamp(f32(ratio) / 4.0, 0, 1)
		rl.DrawRectangleRec(
			rl.Rectangle{bar.x, bar.y, bar.width * frac, bar.height},
			COL_ACCENT,
		)
	} else {
		draw_text("--", 14, y, 28, COL_MUTED)
	}

	// --- plant selection ---
	y += 68
	rl.DrawLine(14, y, WIN_W - 14, y, COL_PANEL)
	y += 12
	draw_text("PLANTS", 14, y, 12, COL_MUTED)
	y += 20

	if !s.have_window {
		draw_text("no game window", 14, y, 14, COL_WARN)
	} else if !s.have_seed_count {
		draw_text("reading seed slots...", 14, y, 14, COL_MUTED)
	} else {
		// The live SeedBank supplies this count. The shovel sits exactly one
		// packet pitch after the final slot.
		draw_text(fmt.ctprintf("level has %d plants", s.plant_count), 14, y + 5, 13, COL_MUTED)

		shovel_key := int(s.plant_count) + 1
		if shovel_key <= 10 {
			draw_text(
				fmt.ctprintf("shovel = X or %d", shovel_key == 10 ? 0 : shovel_key),
				190,
				y + 5,
				13,
				COL_ACCENT,
			)
		} else {
			draw_text("shovel = X", 190, y + 5, 13, COL_ACCENT)
		}

		y += 32
		// One pip per packet, plus a shovel pip in the slot just past them.
		n := int(s.plant_count)
		for i in 0 ..< n {
			px := f32(14 + i * 31)
			r := rl.Rectangle{px, f32(y), 26, 22}
			hot := s.last_slot_ok && s.last_slot == i && s.slot_flash > 0
			rl.DrawRectangleRec(r, hot ? COL_ACCENT : COL_PANEL)
			label := fmt.ctprintf("%d", i == 9 ? 0 : i + 1)
			tw := measure_text(label, 13)
			draw_text(label, i32(px + (26 - f32(tw)) / 2), y + 5, 13, hot ? COL_BG : COL_MUTED)
		}
		sx := f32(14 + n * 31)
		if sx + 26 <= WIN_W - 14 {
			sr := rl.Rectangle{sx, f32(y), 26, 22}
			shot := s.shovel_flash > 0
			rl.DrawRectangleRec(sr, shot ? COL_ACCENT : COL_PANEL)
			rl.DrawRectangleLinesEx(sr, 1, COL_ACCENT_DIM)
			tw := measure_text("X", 13)
			draw_text("X", i32(sx + (26 - f32(tw)) / 2), y + 5, 13, shot ? COL_BG : COL_ACCENT)
		}
	}

	// --- auto collect ---
	y = 390
	rl.DrawLine(14, y, WIN_W - 14, y, COL_PANEL)
	y += 12
	draw_text("AUTO COLLECT", 14, y, 12, COL_MUTED)
	y += 20
	auto_rect := rl.Rectangle{14, f32(y), WIN_W - 28, 38}
	active_col := s.collect_flash > 0 ? COL_TEXT : COL_BG
	rl.DrawRectangleRec(auto_rect, s.auto_collect ? COL_ACCENT : COL_PANEL)
	rl.DrawRectangleLinesEx(auto_rect, 1, s.auto_collect ? COL_ACCENT : COL_ACCENT_DIM)
	label: cstring = s.auto_collect ? "ON  -  A to disable" : "OFF  -  A to enable"
	tw := measure_text(label, 15)
	draw_text(label, i32((WIN_W - f32(tw)) / 2), y + 11, 15, s.auto_collect ? active_col : COL_TEXT)
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), auto_rect) &&
	   rl.IsMouseButtonPressed(.LEFT) {
		s.auto_collect = !s.auto_collect
	}

	// --- footer ---
	fy: i32 = WIN_H - 46
	rl.DrawLine(14, fy - 10, WIN_W - 14, fy - 10, COL_PANEL)
	draw_text("ALT forward   SHIFT+ALT back", 14, fy, 12, COL_MUTED)
	draw_text("A collect   1-9,0 plant   X shovel", 14, fy + 16, 12, COL_MUTED)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_TOPMOST, .VSYNC_HINT})
	rl.InitWindow(WIN_W, WIN_H, "PvZ QoL Mod")
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
	ui_font = rl.LoadFontFromMemory(".ttf", raw_data(ROBOTO_DATA), i32(len(ROBOTO_DATA)), 32, nil, 0)
	custom_font_loaded := rl.IsFontValid(ui_font)
	if custom_font_loaded {
		rl.SetTextureFilter(ui_font.texture, .BILINEAR)
	} else {
		ui_font = rl.GetFontDefault()
	}
	rl.GuiSetFont(ui_font)

	s: State
	s.steps = [4]Step{{"1x", 1.0}, {"2x", 2.0}, {"3x", 3.0}, {"Custom", 5.0}}
	s.custom = 5.0
	s.status = "waiting for Plants vs. Zombies..."
	s.next_collect = time.tick_now()

	custom_box: i32 = 5
	edit_mode := false

	kw: Key_Watch
	kw.was_down = make(map[i32]bool)
	defer delete(kw.was_down)

	aw: Alt_Watch
	// Blank out ALT for the first couple of seconds. GLFW emits its synthetic
	// ALT a frame or two into the run, and if the game already holds foreground
	// GLFW's focus attempt fails - so IsWindowFocused() never flips and a
	// focus-triggered suppression never arms. A flat settle window is the only
	// thing that reliably covers it.
	aw.settle_frames = 240 // ~4s at 60fps

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

		if s.connected {
			if count, ok := get_seed_slot_count(&s.game); ok {
				s.plant_count = count
				s.have_seed_count = true
			} else {
				s.have_seed_count = false
			}
		}

		if !typing_in_gui(edit_mode) {
			// ALT, not SPACE: space pauses Plants vs. Zombies.
			// Game focus only. Accepting our own panel's focus as well was tried
			// and reverted: GLFW's synthetic ALT fires precisely while the panel
			// is taking focus, so that reopened the spurious-cycle bug.
			alt_note_focus(&aw, bool(rl.IsWindowFocused()))
			focused := s.have_window && game_is_focused(s.window)
			if direction := alt_cycle_direction(&aw, focused); direction != 0 {
				s.index = (s.index + direction + len(s.steps)) % len(s.steps)
				apply_current(&s)
			}
			if s.have_window {
				if pressed(&kw, 'A') && focused {
					s.auto_collect = !s.auto_collect
				}
				for vk in i32('0') ..= i32('9') {
					if pressed(&kw, vk) {
						s.next_collect = time.tick_add(time.tick_now(), COLLECT_INPUT_GRACE)
						if slot, ok := vk_to_slot(vk); ok {
							s.last_slot_ok = select_plant(&s.game, &s.window, slot)
							s.last_slot = slot
							if s.last_slot_ok {
								s.slot_flash = 0.35
							}
						}
					}
				}
				// X picks the shovel: it sits one pitch past the last packet,
				// so its slot index is exactly the plant count.
				if pressed(&kw, 'X') && s.have_seed_count {
					s.next_collect = time.tick_add(time.tick_now(), COLLECT_INPUT_GRACE)
					if select_shovel(&s.window, int(s.plant_count)) {
						s.shovel_flash = 0.35
					}
				}
			}
		}

		kw.primed = true

		// Poll at 20 Hz. Coin::mIsBeingCollected suppresses repeat clicks after
		// the game consumes the posted mouse messages.
		now := time.tick_now()
		if s.auto_collect && s.connected && s.have_window &&
		   time.duration_seconds(time.tick_diff(s.next_collect, now)) >= 0 {
			if auto_collect_tick(&s.game, &s.window) > 0 {
				s.collect_flash = 0.16
			}
			s.next_collect = time.tick_add(now, 50 * time.Millisecond)
		}

		if s.slot_flash > 0 {
			s.slot_flash -= rl.GetFrameTime()
		}
		if s.shovel_flash > 0 {
			s.shovel_flash -= rl.GetFrameTime()
		}
		if s.collect_flash > 0 {
			s.collect_flash -= rl.GetFrameTime()
		}

		// Detect the game going away.
		if s.connected {
			if _, ok := get_speed(&s.game); !ok {
				detach(&s.game)
				s.connected = false
				s.have_window = false
				s.have_seed_count = false
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
	if custom_font_loaded {
		rl.UnloadFont(ui_font)
	}
}
