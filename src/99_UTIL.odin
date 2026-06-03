package game

import fa "sol:fixed_dynamic_array"

import rl "vendor:raylib"

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

kb :: rl.KeyboardKey
Vec2 :: rl.Vector2

exit :: proc(code: int) {
	os.exit(code)
}

slice :: proc {
	fa.slice,
}

subslice :: proc(slice: []$T, start: Maybe(int), end: Maybe(int)) -> []T {
	len := len(slice)

	end := max(min(end.? or_else len, len), 0)
	start := max(start.? or_else 0, 0)

	return slice[:end][start:]
}

get_screen_size :: proc() -> (screen_width: i32, screen_height: i32) {
	if rl.IsWindowFullscreen() {
		m := rl.GetCurrentMonitor()
		screen_width = rl.GetMonitorWidth(m)
		screen_height = rl.GetMonitorHeight(m)
	} else {
		screen_width = rl.GetScreenWidth()
		screen_height = rl.GetScreenHeight()
	}
	return
}

clamp_v :: proc(v: Vec2, min: Vec2, max: Vec2) -> Vec2 {
	return Vec2{math.clamp(v.x, min.x, max.x), math.clamp(v.y, min.y, max.y)}
}

magnitude :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

get_entity_status :: proc(entity: WithHp) -> EntityStatus {
	return .Dead if entity.hp <= 0 else .Alive
}

// check if entity is dead
is_dead :: proc(entity: WithHp) -> bool {
	return get_entity_status(entity) == .Dead
}

@(require_results)
read_entire_file :: proc(
	name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: []byte,
	success: bool,
) {
	return _read_entire_file(name, allocator, loc)
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return _write_entire_file(name, data, truncate)
}

load_settings :: proc() -> Maybe(UserSettings) {
	return _load_settings()
}

report_leaks :: proc(track: ^mem.Tracking_Allocator) {
	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	if len(track.bad_free_array) > 0 {
		fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
		for entry in track.bad_free_array {
			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
	mem.tracking_allocator_destroy(track)
	mem.free(track)
}

@(deferred_out = report_leaks)
set_up_tracking_allocator :: proc() -> ^mem.Tracking_Allocator {
	track := new(mem.Tracking_Allocator)
	mem.tracking_allocator_init(track, context.allocator)
	context.allocator = mem.tracking_allocator(track)
	return track
}
