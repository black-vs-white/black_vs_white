package main_desktop

import game ".."

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"

import sta "sol:stack_tracking_allocator"

when ODIN_DEBUG {
	global_trace_ctx: sta.Context
}

INIT_ARENA_SIZE :: 10 * mem.Megabyte when ODIN_DEBUG else 3 * mem.Megabyte

main :: proc() {
	when !ODIN_DEBUG {
		game.set_cwd_to_exe_dir()
	}

	// Initialize logging, so its available for the rest of the program
	context.logger = log.create_console_logger()

	arena: mem.Arena
	memory := make([]byte, INIT_ARENA_SIZE, context.allocator)
	defer delete(memory)

	mem.arena_init(&arena, memory)
	when #config(PRINT_PEAK_MEMORY_USAGE, false) {
		defer log.infof("PEAK ALLOCATION SIZE (INIT): %v bytes", arena.peak_used)
	}
	allocator := mem.arena_allocator(&arena)
	defer mem.free_all(allocator)

	// Initialize the game first,
	// as we don't actually care about not freeing the memory,
	// because the system will free it when the program exits anyway
	game.init(allocator)

	main_alloc := context.allocator
	// panic on unaccounted allocations
	context.allocator = mem.panic_allocator()

	when ODIN_DEBUG {
		// Create a new allocator for allocations during the game
		// and set up the stack tracking allocator
		// this way we should get an error if we allocate memory
		// after initialization and don't free it before shutdown
		sta.init(&global_trace_ctx)
		defer sta.destroy(&global_trace_ctx)

		track: sta.Stack_Tracking_Allocator
		sta.stack_tracking_allocator_init(&track, context.allocator, &global_trace_ctx)
		defer sta.stack_tracking_allocator_destroy(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
					sta.print_stack_trace(&track, entry.stack_trace)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
					sta.print_stack_trace(&track, entry.stack_trace)
				}
			}
		}

		context.allocator = sta.stack_tracking_allocator(&track)
	}

	for game.should_run() {
		game.game_loop()
	}

	context.allocator = main_alloc
	game.shutdown()
}
