package game

import "core:math/rand"
import fa "sol:fixed_dynamic_array"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

reset_player :: proc(player: ^Player, seed: u64) {
	using player
	gamepad_id = i32(player.id)
	area = player_area(id)
	color.r *= 1 - u8(player.id)
	color.g *= 1 - u8(player.id)
	color.b *= 1 - u8(player.id)
	entity = Entity {
		position       = Vec2{area.x + (area.width / 2), area.y + (area.height / 2)},
		velocity       = Vec2{0, 0},
		dampening      = 0,
		appearance     = g_obj.player_appearance[player.id],
		last_direction = Vec2{-1, 0},
	}

	fa.clear(&player.weapons)
	fa.clear(&player.available_upgrades)
	fa.clear(&player.enemies)
	fa.clear(&player.projectiles)
	fa.clear(&player.pickups)
	fa.clear(&player.used_upgrades)

	exp = {0, u32(calculate_xp_needed(2)), 1, 0}
	iframes = 0
	stats = {
		max_hp        = stat(g_conf.balancing.player.base_hp),
		xp_multiplier = stat(f32(1.0)),
		speed         = stat(g_conf.balancing.player.base_speed),
		pickup_range  = stat(g_conf.balancing.player.base_pickup_range),
	}
	with_hp = {g_conf.balancing.player.base_hp}
	enemy_rng_seed = seed
	item_rng_seed = seed

	next := rand.uint64()
	rand.reset(player.enemy_rng_seed)
	defer rand.reset(next)
	defer player.enemy_rng_seed = rand.uint64()

	for weapon_type in g_conf.init.weapons {
		fa.append(&player.weapons, make_weapon(weapon_type))
	}

	_ = spawn_enemies(
		player,
		g_conf.balancing.enemy.spawn_safe_zone * g_conf.physics.units.size,
		g_conf.init.enemies,
		0,
	)
}

make_player :: proc(id: int, seed: u64) -> Player {
	area := player_area(id)
	entity := Entity {
		position       = Vec2{area.x + (area.width / 2), area.y + (area.height / 2)},
		velocity       = Vec2{0, 0},
		dampening      = 0,
		appearance     = g_obj.player_appearance[id],
		last_direction = Vec2{-1, 0},
	}

	weapons := fa.create(Weapon, g_conf.balancing.player.weapon_count)
	available_upgrades := fa.create(Upgrade, g_conf.balancing.player.upgrade_count)
	enemies := fa.create(Enemy, g_conf.balancing.max_enemies)
	projectiles := fa.create(Projectile, g_conf.performance.max_projectiles.value[BUILD_MODE])
	pickups := fa.create(Pickup, g_conf.performance.max_pickups.value[BUILD_MODE])
	used_upgrades := fa.create(Upgrade, g_conf.performance.max_upgrades.value[BUILD_MODE])

	player := Player {
		id = id,
		color = {1 - u8(id), 1 - u8(id), 1 - u8(id), 1},
		gamepad_id = i32(-1), // disable gamepad for now
		exp = {0, u32(calculate_xp_needed(2)), 1, 0},
		iframes = 0,
		area = area,
		entity = entity,
		stats = {
			max_hp = stat(g_conf.balancing.player.base_hp),
			xp_multiplier = stat(f32(1.0)),
			speed = stat(g_conf.balancing.player.base_speed),
			pickup_range = stat(g_conf.balancing.player.base_pickup_range),
		},
		with_hp = {g_conf.balancing.player.base_hp},
		enemy_rng_seed = seed,
		item_rng_seed = seed,
		weapons = weapons,
		available_upgrades = available_upgrades,
		enemies = enemies,
		projectiles = projectiles,
		pickups = pickups,
		used_upgrades = used_upgrades,
	}

	next := rand.uint64()
	rand.reset(player.enemy_rng_seed)
	defer rand.reset(next)
	defer player.enemy_rng_seed = rand.uint64()

	for weapon_type in g_conf.init.weapons {
		fa.append(&player.weapons, make_weapon(weapon_type))
	}

	_ = spawn_enemies(
		&player,
		g_conf.balancing.enemy.spawn_safe_zone * g_conf.physics.units.size,
		g_conf.init.enemies,
		0,
	)

	return player
}
