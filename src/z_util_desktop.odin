#+build !wasm32
#+build !wasm64p32

package game

import "core:encoding/json"
import "core:os"
import "core:path/filepath"

set_cwd_to_exe_dir :: proc() {
	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)
}

_load_settings :: proc() -> Maybe(UserSettings) {
	config_file :: "assets/settings.json"

	user_settings: UserSettings
	spec := json.Specification.JSON5
	content, success := read_entire_file(config_file)
	if success {
		defer delete(content)
		err := json.unmarshal(content, &user_settings, spec)
		if err == nil {
			return user_settings
		}
	}

	user_settings.key_bindings = {
		g_conf.user_settings.key_bindings.player1,
		g_conf.user_settings.key_bindings.player2,
	}
	user_settings.Z_available_keys = ALLOWED_KEYS

	options := json.Marshal_Options{}
	options.pretty = true
	options.spec = spec
	options.use_enum_names = true
	options.sort_maps_by_key = true
	data, err := json.marshal(user_settings, options)
	if err == nil {
		write_entire_file(config_file, data)
	}
	return user_settings
}

_read_entire_file :: proc(
	name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: []byte,
	success: bool,
) {
	return os.read_entire_file(name, allocator, loc)
}

_write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return os.write_entire_file(name, data, truncate)
}
