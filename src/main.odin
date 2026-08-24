package pvzspeed

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import win "core:sys/windows"
import "core:time"

// Speed steps cycled by SPACE. The last one is user-editable.
Step :: struct {
	label: string,
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
	last_slot:    int, // last plant slot picked, for the UI readout
	last_slot_ok: bool,
}

POLL_MS :: 16 // ~60 Hz key polling

enable_vt :: proc() {
	h := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	mode: win.DWORD
	if win.GetConsoleMode(h, &mode) {
		win.SetConsoleMode(h, mode | win.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
	}
}

// Edge-triggered key check: true only on the transition to pressed.
Key_Watch :: struct {
	was_down: map[i32]bool,
}

pressed :: proc(kw: ^Key_Watch, vk: i32) -> bool {
	down := (u16(win.GetAsyncKeyState(vk)) & 0x8000) != 0
	prev := kw.was_down[vk]
	kw.was_down[vk] = down
	return down && !prev
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
	st := current_step(s)
	set_speed(&s.game, st.speed)
}

// Measure the game's actual update rate so the display reflects reality rather
// than what we merely asked for. Stock rate is 100/sec.
update_measurement :: proc(s: ^State) {
	if !s.connected {
		s.measured = 0
		return
	}
	count, ok := get_update_count(&s.game)
	if !ok {
		return
	}
	now := time.tick_now()
	if s.last_count != 0 {
		elapsed := time.duration_seconds(time.tick_diff(s.last_tick, now))
		if elapsed >= 0.5 {
			delta := f64(count - s.last_count)
			s.measured = delta / elapsed
			s.last_count = count
			s.last_tick = now
		}
	} else {
		s.last_count = count
		s.last_tick = now
	}
}

draw :: proc(s: ^State) {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	// Home cursor + clear screen.
	strings.write_string(&sb, "\x1b[H\x1b[2J")
	strings.write_string(&sb, "\x1b[1;32m  PvZ GOTY - Speed Up Mod\x1b[0m\n")
	strings.write_string(&sb, "  \x1b[90m------------------------------------\x1b[0m\n\n")

	for st, i in s.steps {
		speed := st.speed
		if i == len(s.steps) - 1 {
			speed = s.custom
		}
		marker := "   "
		colour := "\x1b[90m"
		if i == s.index {
			marker = " > "
			colour = "\x1b[1;93m"
		}
		fmt.sbprintf(&sb, "%s%s%-8s %.2fx\x1b[0m\n", colour, marker, st.label, speed)
	}

	strings.write_string(&sb, "\n")
	if s.connected {
		fmt.sbprintf(&sb, "  \x1b[32mconnected\x1b[0m  pid %d\n", s.game.pid)
		if s.measured > 0 {
			ratio := s.measured / BASE_UPDATE_RATE
			fmt.sbprintf(
				&sb,
				"  measured: \x1b[1;36m%.0f updates/sec\x1b[0m  (\x1b[1;36m%.2fx\x1b[0m)\n",
				s.measured,
				ratio,
			)
		} else {
			strings.write_string(&sb, "  measured: ...\n")
		}
	} else {
		fmt.sbprintf(&sb, "  \x1b[33m%s\x1b[0m\n", s.status)
	}

	// Plant selection status.
	if !SEED_CALIBRATED {
		strings.write_string(
			&sb,
			"  plants:   \x1b[33muncalibrated - number keys disabled\x1b[0m\n",
		)
	} else if !s.have_window {
		strings.write_string(&sb, "  plants:   \x1b[33mno game window\x1b[0m\n")
	} else if s.last_slot_ok {
		label := s.last_slot == 9 ? 0 : s.last_slot + 1
		fmt.sbprintf(&sb, "  plants:   ready  (last picked \x1b[1;36m%d\x1b[0m)\n", label)
	} else {
		strings.write_string(&sb, "  plants:   ready\n")
	}

	strings.write_string(&sb, "\n  \x1b[90m------------------------------------\x1b[0m\n")
	strings.write_string(&sb, "  \x1b[1mSPACE\x1b[0m  cycle speed\n")
	strings.write_string(&sb, "  \x1b[1m1-9,0\x1b[0m  select plant\n")
	strings.write_string(&sb, "  \x1b[1mC\x1b[0m      set custom value\n")
	strings.write_string(&sb, "  \x1b[1mQ\x1b[0m      quit (restores 1x)\n")

	fmt.print(strings.to_string(sb))
}

prompt_custom :: proc(s: ^State) {
	fmt.print("\x1b[H\x1b[2J")
	fmt.printf("  Current custom speed: %.2fx\n", s.custom)
	fmt.print("  Enter new speed (0.1 - 100), blank to cancel: ")

	buf: [64]u8
	n, err := os.read(os.stdin, buf[:])
	if err != nil || n <= 0 {
		return
	}
	text := strings.trim_space(string(buf[:n]))
	if text == "" {
		return
	}
	value, ok := strconv.parse_f64(text)
	if !ok || value < 0.1 || value > 100.0 {
		fmt.println("  invalid value, keeping previous")
		time.sleep(900 * time.Millisecond)
		return
	}
	s.custom = value
	s.index = len(s.steps) - 1 // jump to the custom slot
	apply_current(s)
}

main :: proc() {
	enable_vt()

	s: State
	s.steps = [4]Step {
		{"1x", 1.0},
		{"2x", 2.0},
		{"3x", 3.0},
		{"Custom", 5.0},
	}
	s.custom = 5.0
	s.index = 0
	s.status = "starting..."

	kw: Key_Watch
	kw.was_down = make(map[i32]bool)
	defer delete(kw.was_down)

	last_draw := time.tick_now()
	reattach_at := time.tick_now()

	for {
		// (Re)attach on a timer so the tool survives the game restarting.
		if !s.connected && time.duration_seconds(time.tick_diff(reattach_at, time.tick_now())) >= 0 {
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

		if pressed(&kw, win.VK_SPACE) {
			s.index = (s.index + 1) % len(s.steps)
			apply_current(&s)
		}
		if pressed(&kw, 'C') {
			prompt_custom(&s)
			last_draw = {}
		}

		// Number keys pick a seed packet. select_plant() is a no-op unless the
		// game is the focused window, so typing digits elsewhere is inert.
		if s.have_window {
			for vk in i32('0') ..= i32('9') {
				if pressed(&kw, vk) {
					if slot, ok := vk_to_slot(vk); ok {
						s.last_slot_ok = select_plant(s.window, slot)
						s.last_slot = slot
					}
				}
			}
		}
		if pressed(&kw, 'Q') || pressed(&kw, win.VK_ESCAPE) {
			if s.connected {
				set_speed(&s.game, 1.0)
			}
			break
		}

		// Confirm the game is still alive and our object is still valid.
		if s.connected {
			if _, ok := get_speed(&s.game); !ok {
				detach(&s.game)
				s.connected = false
				s.status = "lost connection, waiting..."
			}
		}

		update_measurement(&s)

		if time.duration_seconds(time.tick_diff(last_draw, time.tick_now())) >= 0.1 {
			draw(&s)
			last_draw = time.tick_now()
		}

		time.sleep(POLL_MS * time.Millisecond)
	}

	detach(&s.game)
	fmt.print("\x1b[H\x1b[2J")
	fmt.println("  speed restored to 1x, exiting.")
}
