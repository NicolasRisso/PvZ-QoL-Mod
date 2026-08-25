package pvzspeed

// ---------------------------------------------------------------------------
// Offsets for Plants vs. Zombies GOTY (Steam), DRM-extracted `popcapgame1.exe`.
//
// IMPORTANT: these are NOT for the `PlantsVsZombies.exe` in the Steam folder.
// That file is only a DRM launcher stub. It extracts the real game to
// %ProgramData%\PopCap Games\PlantsVsZombies\popcapgame1.exe, starts it, and
// unlinks it from disk. Everything below refers to that child process.
//
// The image has ASLR disabled (DllCharacteristics = 0x0000), so it always
// loads at 0x00400000 and these absolute addresses are stable.
//
// See docs/FINDINGS.md for how each of these was derived.
// ---------------------------------------------------------------------------

PROCESS_NAME :: "popcapgame1.exe"

// The DRM stub. Only used to give the user a better error message when they
// launched the game but the child process is not up yet.
LAUNCHER_NAME :: "PlantsVsZombies.exe"

IMAGE_BASE :: uintptr(0x0040_0000)
IMAGE_SIZE :: uintptr(0x0041_E000)

// Static pointer to the app object (a LawnApp, derived from Sexy::SexyApp).
// Four globals all alias the same object; we use the first and verify the
// others agree as a sanity check.
GLOBAL_APP_PTR :: uintptr(0x0073_1C50)
GLOBAL_APP_ALIASES :: [3]uintptr{0x0073_1CDC, 0x0073_1D08, 0x0073_1DA0}

// Sexy::SexyApp vtable, recovered via RTTI (TypeDescriptor -> COL -> vftable).
// Used as a build fingerprint: we read the first few entries and compare
// against KNOWN_VTABLE_HEAD before touching anything.
SEXYAPP_VTABLE :: uintptr(0x0070_346C)

// First 4 dwords of the SexyApp vtable on the build this was reversed against.
// If these do not match, we are looking at a different build and MUST NOT
// write, or we would be scribbling into an arbitrary object field.
KNOWN_VTABLE_HEAD :: [8]u32{
	0x0040_1B10, 0x0053_5F90, 0x0053_5F90, 0x0053_5F90,
	0x0053_5F90, 0x0053_5F90, 0x0049_1B40, 0x005D_CA10,
}

// --- Field offsets within the app object -----------------------------------

// The speed multiplier. NOTE: this is an f64, not an f32. Scanning for a
// 4-byte 1.0 finds nothing; the value is 0x3FF0000000000000.
OFF_MULTIPLIER :: uintptr(0x4F0)

// Frame time in milliseconds. Always 10 on a stock build (-> 100 updates/sec).
// Used as a structural sanity check that we resolved a real app object.
OFF_FRAME_TIME :: uintptr(0x4B4)
EXPECTED_FRAME_TIME :: i32(10)

// Monotonic update counter, ticks at 100/sec unmodified. Used to measure the
// effective rate so the tool can verify a speed change actually took effect.
OFF_UPDATE_COUNT :: uintptr(0x4E4)

// Active Board pointer in LawnApp. This GOTY build's LawnApp is 0x100 bytes
// larger than the older 1.0.0.1051 layout commonly documented online.
OFF_BOARD :: uintptr(0x868)

// --- Board / DataArray<Coin> ----------------------------------------------

// Board gained 0x18 bytes in this GOTY build relative to the old layout:
// mApp is +0xA4 and mCoins begins at +0xFC.
OFF_BOARD_APP :: uintptr(0xA4)
OFF_BOARD_COINS :: uintptr(0xFC)       // DataArray<Coin>::mData
OFF_BOARD_COIN_MAX_USED :: uintptr(0x100)
OFF_BOARD_CURSOR :: uintptr(0x150)
OFF_BOARD_SEED_BANK :: uintptr(0x15C)

COIN_STRIDE :: uintptr(0xD8)           // sizeof(Coin) + DataArray item metadata
OFF_COIN_X :: uintptr(0x24)
OFF_COIN_Y :: uintptr(0x28)
OFF_COIN_DEAD :: uintptr(0x38)
OFF_COIN_COLLECTING :: uintptr(0x50)
OFF_COIN_TYPE :: uintptr(0x58)

OFF_OBJECT_WIDTH :: uintptr(0x10)
OFF_OBJECT_HEIGHT :: uintptr(0x14)

// CursorObject::mCursorType. Zero is CURSOR_TYPE_NORMAL (empty hand).
OFF_CURSOR_TYPE :: uintptr(0x30)
CURSOR_TYPE_NORMAL :: i32(0)

OFF_SEED_BANK_NUM_PACKETS :: uintptr(0x24)
OFF_SEED_BANK_PACKETS :: uintptr(0x28)
SEED_PACKET_STRIDE :: uintptr(0x50)

OFF_OBJECT_X :: uintptr(0x08)
OFF_OBJECT_Y :: uintptr(0x0C)

MAX_COIN_ENTRIES :: u32(1024)

BASE_UPDATE_RATE :: 100.0
