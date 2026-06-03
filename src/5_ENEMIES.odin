#+feature dynamic-literals

package game

import ea "sol:expression_evaluator"
import fa "sol:fixed_dynamic_array"

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

// this will spawn a specific amount of enemies near the player
@(require_results)
spawn_enemies :: proc(p: ^Player, min_distance: f32, amount: int, total_kills: u32) -> bool {
	next := rand.uint64()
	rand.reset(p.enemy_rng_seed)
	defer rand.reset(next)
	for _ in 0 ..< amount {
		if !fa.append(&p.enemies, new_enemy(p, min_distance, total_kills)) {
			return false
		}
	}
	return true
}

// create an enemy at a random position around the player
new_enemy :: proc(player: ^Player, min_distance: f32, total_kills: u32) -> Enemy {
	// Generate a random angle between 0 and 2π
	angle := rand.float32_range(0.0, 2.0 * math.PI)

	// Calculate Cartesian coordinates from the angle and minimum distance
	max_distance := min_distance * 2
	offset_x := math.cos(angle) * rand.float32_range(min_distance, max_distance)
	offset_y := math.sin(angle) * rand.float32_range(min_distance, max_distance)

	// Calculate the final position by adding the offset to the player's position
	position := Vec2{player.entity.position.x + offset_x, player.entity.position.y + offset_y}
	position.x = math.clamp(position.x, player.area.x, player.area.x + player.area.width)
	position.y = math.clamp(position.y, player.area.y, player.area.y + player.area.height)

	x := player.entity.position.x - player.area.x
	player.enemy_rng_seed = calculate_new_seed(f32, x, f32, player.entity.position.y)

	hp, err := ea.eval_expr(g_obj.scaling["enemy_hp"], g_conf.variables, g_obj.operators)

	if err != nil {
		panic(fmt.tprint(err))
	}

	return {{}, {i32(hp)}, {position, Vec2{0, 0}, g_obj.enemy_appearance, 0, {}}}
}

enemy_in_range :: proc(player: ^Player, enemy: ^Entity, range: f32) -> bool {
	p_entity := &player.entity

	distance := magnitude(p_entity.position - enemy.position)

	return distance <= range
}

find_nearest_enemy :: proc(player: ^Player) -> ^Entity {
	nearest_enemy: ^Entity = nil
	min_distance: f32 = math.F32_MAX

	p_entity := &player.entity

	for &enemy in slice(&player.enemies) {
		distance := magnitude(p_entity.position - enemy.position)

		if distance < min_distance {
			min_distance = distance
			nearest_enemy = &enemy
		}
	}

	return nearest_enemy
}

hit_enemy :: proc(game: ^StateGame, player: ^Player, enemy: ^Enemy, damage: f32) {
	if damage_entity(enemy, damage) != .Dead {
		if .EnemyGodMode in g_obj.debug_flags {
			return
		}
		enemy.appearance.animation = HurtAnimation {
			60,
			10,
			0,
			0,
			[2]rl.Color{enemy.appearance.color, rl.BEIGE},
		}
		return
	}

	enemy_died(game, player, enemy)
	fa.unordered_remove(&player.enemies, enemy)
}

enemy_died :: proc(game: ^StateGame, player: ^Player, enemy: ^Entity) {
	game.kills += 1

	g_conf.variables["total_kills"] = f32(game.kills)

	appearance := g_obj.xp_appearance
	xp, err := ea.eval_expr(g_obj.scaling["enemy_xp"], g_conf.variables, g_obj.operators)

	if err != nil {
		panic(fmt.tprint(err))
	}

	hp: i32 = 0
	if rand.float32() < g_conf.balancing.pickup.health_pack_chance {
		xp = 0
		hp = 5 + rand.int31_max(16)
		appearance = g_obj.health_pack_appearance
	}
	fa.append(
		&player.pickups,
		Pickup{false, u32(xp), hp, Entity{enemy.position, Vec2{}, appearance, 0, {}}},
	)

	// spawn new enemies for the other player
	p_other := &g_obj.players[1 - player.id]
	ok := spawn_enemies(
		p_other,
		g_conf.balancing.enemy.spawn_safe_zone * g_conf.physics.units.size,
		g_conf.balancing.enemies_per_kill,
		game.kills,
	)
	if !ok {
		set_loser(game, p_other)
		return
	}
}
