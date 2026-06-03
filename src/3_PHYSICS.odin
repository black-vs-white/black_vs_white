package game

import fa "sol:fixed_dynamic_array"
import fa_iter "sol:fixed_dynamic_array/iter"

import rl "vendor:raylib"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

import "core:math"

// Information about a collision
Collision :: struct {
	// A normalized vector pointing into the direction of the collision
	direction: Vec2,
	// The amount of overlap between the two entities
	overlap:   f32,
}

get_collision :: proc(self, other: ^Entity) -> (col: Collision, ok: bool) {
	// Handle different collision_box types
	switch &hb_self in self.appearance.bbox {
	case CircleCollisionBox:
		switch &hb_other in other.appearance.bbox {
		case CircleCollisionBox:
			col, ok = get_collision_CC(
				self.position,
				hb_self.radius,
				other.position,
				hb_other.radius,
			)

		case RectangleCollisionBox, SquareCollisionBox:
			rect_size: Vec2
			#partial switch &hb_inner in other.appearance.bbox {
			case RectangleCollisionBox:
				rect_size = Vec2{hb_inner.width, hb_inner.height}
			case SquareCollisionBox:
				rect_size = Vec2{hb_inner.size, hb_inner.size}
			}

			col, ok = get_collision_CR(self.position, hb_self.radius, other.position, rect_size)
		}

	case RectangleCollisionBox, SquareCollisionBox:
		self_rect_size: Vec2
		#partial switch &hb_self in self.appearance.bbox {
		case RectangleCollisionBox:
			self_rect_size = Vec2{hb_self.width, hb_self.height}
		case SquareCollisionBox:
			self_rect_size = Vec2{hb_self.size, hb_self.size}
		}

		switch &hb_other in other.appearance.bbox {
		case CircleCollisionBox:
			col, ok = get_collision_CR(
				other.position,
				hb_other.radius,
				self.position,
				self_rect_size,
			)

		case RectangleCollisionBox, SquareCollisionBox:
			other_rect_size: Vec2
			#partial switch &hb_inner in other.appearance.bbox {
			case RectangleCollisionBox:
				other_rect_size = Vec2{hb_inner.width, hb_inner.height}
			case SquareCollisionBox:
				other_rect_size = Vec2{hb_inner.size, hb_inner.size}
			}

			col, ok = get_collision_RR(
				self.position,
				self_rect_size,
				other.position,
				other_rect_size,
			)
		}
	}

	return
}

get_collision_CR :: proc(
	circle_pos: Vec2,
	circle_radius: f32,
	other: Vec2,
	other_size: Vec2,
) -> (
	Collision,
	bool,
) {
	circle_pos := circle_pos
	other := other
	other = other - (other_size / 2)
	closest := clamp_v(circle_pos, other, other + other_size)

	collision_vector := closest - circle_pos
	distance := magnitude(collision_vector)
	direction := collision_vector / distance

	overlap := circle_radius - distance
	return {direction, overlap}, distance <= circle_radius
}

abs_vec2 :: proc(v: Vec2) -> Vec2 {
	return {abs(v.x), abs(v.y)}
}

get_collision_RR :: proc(
	self: Vec2,
	self_size: Vec2,
	other: Vec2,
	other_size: Vec2,
) -> (
	col: Collision,
	ok: bool,
) {
	// Centers of each rectangle
	delta := other - self
	direction := delta / magnitude(delta)

	total_half_size := (self_size + other_size) / 2
	overlap := total_half_size - abs_vec2(delta)

	// Are we overlapping on both axes?
	if overlap.x > 0 && overlap.y > 0 {
		// Choose axis of least penetration
		if overlap.x < overlap.y {
			direction = {math.sign(delta.x), 0}
			penetration := overlap.x
			return {direction, penetration}, true
		} else {
			direction = {0, math.sign(delta.y)}
			penetration := overlap.y
			return {direction, penetration}, true
		}
	}

	// No collision - return normalized direction and distance to center
	return {direction, magnitude(delta)}, false
}

get_collision_CC :: proc(
	self: Vec2,
	self_radius: f32,
	other: Vec2,
	other_radius: f32,
) -> (
	Collision,
	bool,
) {
	// Calculate the vector between the circles
	collision_vector: Vec2 = other - self
	distance := magnitude(collision_vector)

	direction := collision_vector / distance

	// Check if they are colliding
	min_distance := self_radius + other_radius

	overlap := min_distance - distance
	return {direction, overlap}, distance < min_distance
}

resolve_collision_with_player :: proc(enemy: ^Entity, col: Collision) {
	enemy.position -= col.direction * col.overlap
}

resolve_collision_with_entity :: proc(self, other: ^Entity, col: Collision) {
	self.position -= col.direction * (col.overlap / 2)
	other.position += col.direction * (col.overlap / 2)
}

set_loser :: proc(game: ^StateGame, player: ^Player) {
	game.game_over = true
	if game.winner == nil {
		game.winner = Winner(1 - player.id)
		return
	}
	if int(game.winner.?) == player.id {
		game.winner = .Draw
	}
}

handle_collisions :: proc(game: ^StateGame, player: ^Player) {
	player.entity.dampening = 0

	for &enemy in slice(&player.enemies) {
		// Check and resolve collision with player
		if col, colliding := get_collision(&enemy, &player.entity); colliding {
			if .GodMode not_in g_obj.debug_flags && player.iframes == 0 {
				player.iframes = u32(g_conf.balancing.player.iframes * f32(FPS))
				if damage_entity(player, g_conf.balancing.enemy.touch_damage) == .Dead {
					set_loser(game, player)
					return
				}
				player.entity.appearance.animation = HurtAnimation {
					player.iframes,
					10,
					0,
					0,
					[2]rl.Color{enemy.appearance.color, rl.ORANGE},
				}
			}
			player.entity.dampening = g_conf.balancing.enemy.dampening
			resolve_collision_with_player(&enemy, col)
		}
	}

	// run multiple times to make collisions look smoother
	for _ in 0 ..< g_conf.performance.collision_detection_iterations.value[BUILD_MODE] {

		// in order to keep the collision code performant,
		// we only check collision once per entity pair.
		// to do that take all entities except the last one
		// and check them against all other entities,
		// starting from the next one.
		// this ensures that we don't check the same pair twice,
		// as well as not checking an entity against itself.
		for &enemy, e in subslice(slice(&player.enemies), nil, fa.len(player.enemies) - 2) {
			// Check and resolve collisions with other enemies
			for &other in subslice(slice(&player.enemies), e + 1, nil) {
				if col, colliding := get_collision(&enemy, &other); colliding {
					resolve_collision_with_entity(&enemy, &other, col)
				}
			}
		}
	}

	it := fa_iter.make_sync_iter(&player.pickups)
	for pickup in fa_iter.next_ref(&it) {
		col, colliding := get_collision(&pickup.entity, &player.entity)
		distance := -col.overlap
		if distance <= player.stats.pickup_range.value * g_conf.physics.units.size {
			pickup.picked_up = true
		}
		if colliding {
			player.exp.current += u32(f32(pickup.xp) * player.stats.xp_multiplier.value)
			player.hp = min(player.hp + pickup.hp, player.stats.max_hp.value)
			fa.unordered_remove(&player.pickups, pickup)
		}
	}
}
