package game

import ea "sol:expression_evaluator"

import "base:runtime"
import "core:encoding/json"
import rl "vendor:raylib"

import "core:fmt"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

GameConfig_Debug :: struct {
	god_mode:                        bool,
	render_grid:                     bool,
	render_grid_text:                bool,
	entity_draw_positions:           bool,
	player_show_collision_boxes:     bool,
	projectile_show_collision_boxes: bool,
	enemy_show_collision_boxes:      bool,
	enemy_freeze:                    bool,
	enemy_god_mode:                  bool,
}

Expression :: struct {
	formula: string,
}

DebugValue :: struct($T: typeid) {
	value: [2]T,
}

GameConfig_Texture :: struct {
	path:     cstring,
	offset_x: f32,
	offset_y: f32,
	invert:   bool,
}

Range :: struct {
	min: f32,
	max: f32,
}

GameConfig :: struct {
	debug:         GameConfig_Debug,
	init:          struct {
		weapons: []WeaponType,
		enemies: int,
	},
	assets:        struct {
		textures: map[string]GameConfig_Texture,
	},
	variables:     map[string]ea.Number,
	balancing:     struct {
		enemies_per_kill: int,
		max_enemies:      int,
		scaling:          map[string]string,
		weapon_stats:     [WeaponType]struct {
			damage:   f32,
			speed:    f32,
			cooldown: f32,
			area:     f32,
		},
		player:           struct {
			base_hp:           i32,
			base_pickup_range: f32,
			base_speed:        f32,
			iframes:           f32,
			weapon_count:      int,
			upgrade_count:     int,
		},
		enemy:            struct {
			base_hp:         i32,
			base_speed:      f32,
			base_xp:         u32,
			dampening:       f32,
			touch_damage:    f32,
			spawn_safe_zone: f32,
		},
		pickup:           struct {
			follow_speed:       f32,
			health_pack_chance: f32,
			radius:             f32,
		},
		upgrades:         struct {
			general:  struct {
				chance_for_percent_upgrade: f32,
				percent:                    Range,
				flat:                       Range,
			},
			per_type: [UpgradeType]struct {
				chance_for_percent_upgrade: Maybe(f32),
				percent:                    Maybe(Range),
				flat:                       Maybe(Range),
				weight:                     Maybe(int),
			},
		},
	},
	general:       struct {
		zoom:      f32,
		log_level: DebugValue(runtime.Logger_Level),
	},
	graphics:      struct {
		background: string,
		pickups:    struct {
			exp_orb_color:     rl.Color,
			health_pack_color: rl.Color,
		},
		player:     [2]struct {
			texture: string,
		},
		enemy:      struct {
			color:   rl.Color,
			texture: string,
		},
	},
	physics:       struct {
		units:  struct {
			size:  f32,
			speed: f32,
		},
		player: struct {
			bbox: RectangleCollisionBox,
		},
		enemy:  struct {
			bbox: RectangleCollisionBox,
		},
	},
	performance:   struct {
		collision_detection_iterations: DebugValue(i32),
		max_projectiles:                DebugValue(int),
		max_pickups:                    DebugValue(int),
		max_upgrades:                   DebugValue(int),
	},
	user_settings: struct {
		key_bindings: struct {
			player1: Controls,
			player2: Controls,
		},
	},
}

player_area :: proc(player_id: int) -> rl.Rectangle {
	return {
		f32(player_id) * f32(PLAYER_AREA_WIDTH + g_obj.player_size),
		0,
		PLAYER_AREA_WIDTH,
		PLAYER_AREA_HEIGHT,
	}
}

write_config :: proc() {
	data, err := json.marshal(g_conf, {pretty = true, use_enum_names = true})
	assert(err == nil, "Failed to marshal config")

	_ = write_entire_file("override.json", data)
}

@(private = "file")
DEFAULT_CONFIG :: #load("../defaults/config.json")

equal :: proc(from_file: json.Value, re_parsed: json.Value) -> bool {
	inner_equal :: proc(
		key_or_index: ^[dynamic]string,
		from_file: json.Value,
		re_parsed: json.Value,
	) -> bool {
		switch a in from_file {
		case json.Null:
			_, ok := re_parsed.(json.Null)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
		case json.Boolean:
			b, ok := re_parsed.(json.Boolean)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			if a != b {
				log.errorf("Value mismatch at key %v: %v != %v", key_or_index, a, b)
				return false
			}
		case json.Float:
			b, ok := re_parsed.(json.Float)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			if abs(a - b) > 0.0001 {
				log.errorf("Value mismatch at key %v: %v != %v", key_or_index, a, b)
				return false
			}
		case json.Integer:
			b, ok := re_parsed.(json.Integer)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			if a != b {
				log.errorf("Value mismatch at key %v: %v != %v", key_or_index, a, b)
				return false
			}
		case json.String:
			b, ok := re_parsed.(json.String)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			if a != b {
				log.errorf("Value mismatch at key %v: %v != %v", key_or_index, a, b)
				return false
			}
		case json.Array:
			b, ok := re_parsed.(json.Array)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			if len(a) != len(b) {
				log.errorf("Array length mismatch at key: %v", key_or_index)
				return false
			}
			for i := 0; i < len(a); i += 1 {
				append(key_or_index, fmt.tprintf("%v", i))
				defer pop(key_or_index)

				if !inner_equal(key_or_index, a[i], b[i]) {
					return false
				}
			}
		case json.Object:
			b, ok := re_parsed.(json.Object)
			if !ok {
				log.errorf("Type mismatch at key: %v", key_or_index)
				return false
			}
			for key, item in a {
				append(key_or_index, key)
				defer pop(key_or_index)
				if key not_in b {
					log.errorf("Key mismatch at key: %v", key_or_index)
					return false
				}
				if !inner_equal(key_or_index, item, b[key]) {
					return false
				}
			}
		}
		return true
	}

	index := make([dynamic]string, 0)
	defer delete(index)
	append(&index, "ROOT")
	defer pop(&index)
	return inner_equal(&index, from_file, re_parsed)
}

validate :: proc(default_config: GameConfig) {
	original, err := json.parse(DEFAULT_CONFIG)
	defer json.destroy_value(original)

	data, m_err := json.marshal(default_config, {pretty = true, use_enum_names = true})
	assert(m_err == nil, "Could not marshal config")
	defer delete(data)

	re_parsed: json.Value
	re_parsed, err = json.parse(data)
	assert(err == nil, "Could not parse config")
	defer json.destroy_value(re_parsed)

	assert(equal(original, re_parsed), "Config is not equal after marshalling and parsing")
}

load_game_config :: proc() -> GameConfig {
	default_config: GameConfig
	err := json.unmarshal(DEFAULT_CONFIG, &default_config)
	assert(err == nil, "Failed to load config file")

	when ODIN_DEBUG {
		validate(default_config)
	}

	config := default_config

	when ALLOW_CONFIG_OVERRIDE {
		config_file := "override.json"
		data, _ := read_entire_file(config_file)

		err = json.unmarshal(data, &config)
		if err != nil {
			config = default_config
		}
	}

	assert(config.init.enemies > 0, "config.init.enemies must be 1 or higher")
	assert(
		config.init.enemies <= config.balancing.max_enemies,
		"config.init.enemies must be smaller or equal to config.balancing.max_enemies",
	)
	assert(config.balancing.max_enemies > 0, "config.balancing.max_enemies must be 1 or higher")
	assert(
		config.balancing.enemy.spawn_safe_zone > 0,
		"config.enemy.spawn_safe_zone must be 1 or higher",
	)
	assert(config.balancing.player.base_hp > 0, "config.player.base_hp must be 1 or higher")
	assert(config.balancing.player.base_speed > 0, "config.player.base_speed must be 1 or higher")
	assert(config.balancing.enemy.base_hp > 0, "config.enemy.base_hp must be 1 or higher")
	assert(config.balancing.enemy.dampening >= 0, "config.enemy.dampening must be 0 or higher")
	assert(config.balancing.enemy.base_speed > 0, "config.enemy.base_speed must be 1 or higher")
	assert(
		config.balancing.player.weapon_count > 0,
		"config.player.weapon_count must be 1 or higher",
	)
	assert(
		config.performance.collision_detection_iterations.value[BUILD_MODE] > 0,
		"config.performance.collision_detection_iterations must be 1 or higher",
	)

	config.variables["total_kills"] = u32(0)

	config.variables["enemies_per_kill"] = config.balancing.enemies_per_kill
	config.variables["max_enemies"] = config.balancing.max_enemies

	config.variables["enemy.base_hp"] = config.balancing.enemy.base_hp
	config.variables["enemy.base_speed"] = config.balancing.enemy.base_speed
	config.variables["enemy.base_xp"] = config.balancing.enemy.base_xp
	config.variables["enemy.dampening"] = config.balancing.enemy.dampening
	config.variables["enemy.touch_damage"] = config.balancing.enemy.touch_damage
	config.variables["enemy.spawn_safe_zone"] = config.balancing.enemy.spawn_safe_zone

	config.variables["player.base_hp"] = config.balancing.player.base_hp
	config.variables["player.base_pickup_range"] = config.balancing.player.base_pickup_range
	config.variables["player.base_speed"] = config.balancing.player.base_speed
	config.variables["player.iframes"] = config.balancing.player.iframes
	config.variables["player.upgrade_count"] = config.balancing.player.upgrade_count
	config.variables["player.weapon_count"] = config.balancing.player.weapon_count

	config.variables["pickup.follow_speed"] = config.balancing.pickup.follow_speed
	config.variables["pickup.health_pack_chance"] = config.balancing.pickup.health_pack_chance
	config.variables["pickup.radius"] = config.balancing.pickup.radius

	config.variables["weapon_stats.Projectile.area"] =
		config.balancing.weapon_stats[.Projectile].area
	config.variables["weapon_stats.Projectile.cooldown"] =
		config.balancing.weapon_stats[.Projectile].cooldown
	config.variables["weapon_stats.Projectile.damage"] =
		config.balancing.weapon_stats[.Projectile].damage
	config.variables["weapon_stats.Projectile.speed"] =
		config.balancing.weapon_stats[.Projectile].speed

	config.variables["weapon_stats.Zone.area"] = config.balancing.weapon_stats[.Zone].area
	config.variables["weapon_stats.Zone.cooldown"] = config.balancing.weapon_stats[.Zone].cooldown
	config.variables["weapon_stats.Zone.damage"] = config.balancing.weapon_stats[.Zone].damage
	config.variables["weapon_stats.Zone.speed"] = config.balancing.weapon_stats[.Zone].speed

	return config
}
