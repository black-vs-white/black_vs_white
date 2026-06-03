package game

import fa "sol:fixed_dynamic_array"
import rl "vendor:raylib"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log


WeaponType :: enum {
	Projectile,
	Zone,
}

Stat :: struct($T: typeid) {
	base:  T,
	value: T,
}

Weapon :: struct {
	type:      WeaponType,
	remaining: u32,
	cooldown:  Stat(f32),
	speed:     Stat(f32),
	area:      Stat(f32),
	damage:    Stat(f32),
}

stat :: proc(base: $T) -> Stat(T) {
	return {base, base}
}

make_weapon :: proc(weapon: WeaponType) -> Weapon {
	stats := g_conf.balancing.weapon_stats[weapon]
	return Weapon {
		type = weapon,
		remaining = u32(stats.cooldown * f32(FPS)),
		cooldown = stat(stats.cooldown),
		speed = stat(stats.speed),
		area = stat(stats.area),
		damage = stat(stats.damage),
	}
}

handle_weapons :: proc(game: ^StateGame, player: ^Player) {
	for &weapon in slice(&player.weapons) {
		#partial switch weapon.type {
		case .Projectile:
			weapon.remaining -= 1
			if weapon.remaining > 0 {
				continue
			}
			weapon.remaining = u32(weapon.cooldown.value * f32(FPS))
			enemy := find_nearest_enemy(player)
			if enemy == nil {
				continue
			}

			col, _ := get_collision(&player.entity, enemy)
			pos :=
				player.entity.position +
				col.direction * get_min_size(player.entity.appearance.bbox)
			vel := col.direction * weapon.speed.value * g_conf.physics.units.speed
			size := weapon.area.value * g_conf.physics.units.size
			fa.append(
				&player.projectiles,
				Projectile {
					player,
					weapon.damage.value,
					Entity {
						pos,
						vel,
						{
							rl.BLUE,
							ShadowCircle{size / 2, player.entity.appearance.color},
							CircleCollisionBox{radius = size / 2},
							nil,
						},
						0,
						{},
					},
				},
			)
		case WeaponType.Zone:
			for &enemy in slice(&player.enemies) {
				if enemy_in_range(player, &enemy, weapon.area.value * g_conf.physics.units.size) {
					remaining := enemy.hit_cooldown[weapon.type]

					if remaining > 0 {
						remaining -= 1
						continue
					}
					enemy.hit_cooldown[weapon.type] = u32(weapon.cooldown.value * f32(FPS))
					hit_enemy(game, player, &enemy, weapon.damage.value)
					if game.game_over {
						return
					}
				}
			}
		}
	}
}
