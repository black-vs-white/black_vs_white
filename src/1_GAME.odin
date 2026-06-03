package game

import ea "sol:expression_evaluator"
import fa "sol:fixed_dynamic_array"
import fa_iter "sol:fixed_dynamic_array/iter"

import "base:runtime"
import "core:c"
import "core:crypto/hash"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import rl "vendor:raylib"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

g_obj: GameObject
g_conf: GameConfig

DebugFlag :: enum {
	DebugMode,
	GodMode,
	RenderGrid,
	RenderGridText,
	EntityDrawPositions,
	PlayerShowCollisionBoxes,
	ProjectileShowCollisionBoxes,
	EnemyShowCollisionBoxes,
	EnemyFreeze,
	EnemyGodMode,
}

DebugFlags :: bit_set[DebugFlag]

arena: mem.Arena
memory: []byte
allocator: mem.Allocator

init :: proc(init_allocator := context.allocator) {
	memory = make([]byte, RUNTIME_ARENA_SIZE)
	mem.arena_init(&arena, memory)
	allocator = mem.arena_allocator(&arena)

	old_context := context
	defer context = old_context
	context.allocator = init_allocator
	context.temp_allocator = init_allocator
	g_conf = load_game_config()

	g_obj.running = true
	g_obj.screen_width = i32(1920 * 0.60)
	g_obj.screen_height = i32(1080 * 0.60)

	g_obj.debug_flags = {}

	g_obj.operators = ea.make_default_operator_map()

	for name, formula in g_conf.balancing.scaling {
		eb, err := ea.parse(formula)
		assert(err == nil, fmt.tprintf("Error parsing formula %s: %v", name, err))
		g_obj.scaling[name] = eb
	}

	count: int = 0
	for ut in UpgradeType {
		count += g_conf.balancing.upgrades.per_type[ut].weight.? or_else 1
	}

	g_obj.weighted_upgrade_types = fa.create(UpgradeType, count)

	for ut in UpgradeType {
		weight := g_conf.balancing.upgrades.per_type[ut].weight.? or_else 1
		for _ in 0 ..< int(weight) {
			fa.append(&g_obj.weighted_upgrade_types, ut)
		}
	}

	when ODIN_DEBUG {
		g_obj.debug_flags += {.DebugMode}
		if g_conf.debug.god_mode {
			g_obj.debug_flags += {.GodMode}
		}
		if g_conf.debug.render_grid {
			g_obj.debug_flags += {.RenderGrid}
		}
		if g_conf.debug.render_grid_text {
			g_obj.debug_flags += {.RenderGridText}
		}
		if g_conf.debug.entity_draw_positions {
			g_obj.debug_flags += {.EntityDrawPositions}
		}
		if g_conf.debug.player_show_collision_boxes {
			g_obj.debug_flags += {.PlayerShowCollisionBoxes}
		}
		if g_conf.debug.projectile_show_collision_boxes {
			g_obj.debug_flags += {.ProjectileShowCollisionBoxes}
		}
		if g_conf.debug.enemy_show_collision_boxes {
			g_obj.debug_flags += {.EnemyShowCollisionBoxes}
		}
		if g_conf.debug.enemy_freeze {
			g_obj.debug_flags += {.EnemyFreeze}
		}
		if g_conf.debug.enemy_god_mode {
			g_obj.debug_flags += {.EnemyGodMode}
		}
	}

	tmp := load_settings()
	if tmp != nil {
		g_obj.settings = tmp.?
	} else {
		g_obj.settings = UserSettings {
			key_bindings     = {
				g_conf.user_settings.key_bindings.player1,
				g_conf.user_settings.key_bindings.player2,
			},
			Z_available_keys = ALLOWED_KEYS,
		}
	}

	g_obj.players = {make_player(0, 0), make_player(1, 0)}

	when !#config(RAYLIB_LOGGING, false) {
		rl.SetTraceLogLevel(.NONE)
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})

	title := WINDOW_TITLE

	when ODIN_DEBUG {
		title = WINDOW_TITLE_DEBUG
	}

	rl.InitWindow(g_obj.screen_width, g_obj.screen_height, title)

	when ODIN_OS != .JS {
		scaling := rl.GetWindowScaleDPI()
		g_conf.general.zoom *= (scaling.x + scaling.y) / 2

		w := rl.GetRenderWidth()
		h := rl.GetRenderHeight()

		g_obj.last_screen_width, g_obj.last_screen_height = g_obj.screen_width, g_obj.screen_height
		g_obj.screen_width = i32(f32(w) * scaling.x)
		g_obj.screen_height = i32(f32(h) * scaling.y)

		rl.SetWindowSize(g_obj.screen_width, g_obj.screen_height)

		pos := rl.GetWindowPosition()
		pos +=
			(Vec2 {
					f32(g_obj.last_screen_width - g_obj.screen_width),
					f32(g_obj.last_screen_height - g_obj.screen_height),
				} /
				2)

		rl.SetWindowPosition(i32(pos.x), i32(pos.y))

		rl.HideCursor()
	}

	rl.SetExitKey(kb.KEY_NULL)

	when !ODIN_DEBUG {
		rl.ToggleBorderlessWindowed()
	}

	g_obj.screen_width, g_obj.screen_height = get_screen_size()
	g_obj.last_screen_width, g_obj.last_screen_height = g_obj.screen_width, g_obj.screen_height

	g_obj.states = fa.create(State, 10)

	when ODIN_OS == .JS {
		push_state(
			StateMenu {
				{
					1,
					rl.GetFontDefault(),
					[MAIN_MENU_ITEMS]MenuItem(MainMenuAction) {
						{"Play", .Play},
						// {"Settings", .Options},
					},
				},
			},
		)
	} else {
		push_state(
			StateMenu {
				{
					0,
					rl.GetFontDefault(),
					[MAIN_MENU_ITEMS]MenuItem(MainMenuAction) {
						{"Play", .Play},
						// {"Settings", .Options},
						{"Exit", .Exit},
					},
				},
			},
		)
	}

	for name, asset in g_conf.assets.textures {
		image := rl.LoadImage(asset.path)
		if asset.invert {
			rl.ImageColorInvert(&image)
		}
		texture := TextureContainer {
			rl.LoadTextureFromImage(image),
			Vec2{asset.offset_x, asset.offset_y},
			Vec2{f32(image.width), f32(image.height)},
		}
		rl.SetTextureFilter(texture.texture, rl.TextureFilter.POINT)
		g_obj.assets[name] = texture
	}

	{
		g_obj.player_appearance[0] = {
			animation = nil,
			color     = rl.WHITE,
			bbox      = g_conf.physics.player.bbox,
			type      = g_obj.assets[g_conf.graphics.player[0].texture],
		}
		g_obj.player_appearance[1] = {
			animation = nil,
			color     = rl.WHITE,
			bbox      = g_conf.physics.player.bbox,
			type      = g_obj.assets[g_conf.graphics.player[1].texture],
		}
	}
	g_obj.player_size = get_max_size(g_conf.physics.player.bbox)

	{
		g_obj.enemy_appearance = {
			animation = nil,
			color     = rl.RED,
			bbox      = g_conf.physics.enemy.bbox,
			type      = g_obj.assets[g_conf.graphics.enemy.texture],
		}
	}
	g_obj.enemy_size = get_max_size(g_obj.enemy_appearance.bbox)

	g_obj.xp_appearance = {
		animation = nil,
		color = g_conf.graphics.pickups.exp_orb_color,
		bbox = CircleCollisionBox{radius = g_conf.balancing.pickup.radius},
		type = Circle{g_conf.balancing.pickup.radius},
	}
	g_obj.health_pack_appearance = {
		animation = nil,
		color = g_conf.graphics.pickups.health_pack_color,
		bbox = CircleCollisionBox{radius = g_conf.balancing.pickup.radius},
		type = Circle{g_conf.balancing.pickup.radius},
	}

	when ODIN_OS == .JS {
		g_obj.shader_magic = rl.LoadShader(nil, "assets/magic_web.fs")
	} else {
		g_obj.shader_magic = rl.LoadShader(nil, "assets/magic_desktop.fs")
	}
	assert(rl.IsShaderValid(g_obj.shader_magic), "Shader magic is not valid")

	g_obj.shader_magic_center = rl.GetShaderLocation(g_obj.shader_magic, "center")
	g_obj.shader_magic_time = rl.GetShaderLocation(g_obj.shader_magic, "time")
	g_obj.shader_magic_resolution = rl.GetShaderLocation(g_obj.shader_magic, "resolution")

	g_obj.background = rl.LoadTexture("assets/light_background.png")

	set_shader_resolutions()

	// Create initial render textures for both player views
	g_obj.screen_textures = [2]rl.RenderTexture {
		rl.LoadRenderTexture(g_obj.screen_width / 2, g_obj.screen_height),
		rl.LoadRenderTexture(g_obj.screen_width / 2, g_obj.screen_height),
	}

	g_obj.zoom = g_conf.general.zoom

	g_obj.cameras = [2]rl.Camera2D{rl.Camera2D{}, rl.Camera2D{}}
	g_obj.cameras[0].zoom = g_obj.zoom
	g_obj.cameras[1].zoom = g_obj.zoom

	rl.SetTargetFPS(FPS)
}

set_shader_resolution :: proc(shader: rl.Shader, location: i32) {
	rl.SetShaderValue(
		shader,
		location,
		&Vec2{f32(g_obj.screen_width), f32(g_obj.screen_height)},
		.VEC2,
	)
}


TextureContainer :: struct {
	texture: rl.Texture,
	offset:  Vec2,
	size:    Vec2,
}

Circle :: struct {
	radius: f32,
}

ShadowCircle :: struct {
	radius:       f32,
	shadow_color: rl.Color,
}

TextureOrShape :: union {
	TextureContainer,
	Circle,
	ShadowCircle,
}

Appearance :: struct {
	color:     rl.Color,
	type:      TextureOrShape,
	bbox:      CollisionBox,
	animation: Animation,
}

UserSettings :: struct {
	key_bindings:     [2]Controls,
	Z_available_keys: []rl.KeyboardKey,
}

MainMenuAction :: enum {
	Play,
	Options,
	Exit,
}

PauseMenuAction :: enum {
	Resume,
	ToMainMenu,
	Exit,
}

MenuItem :: struct($Action: typeid) {
	text:   cstring,
	action: Action,
}

StateMenu :: struct {
	menu: Menu(MAIN_MENU_ITEMS, MainMenuAction),
}

StateOptions :: struct {
}

Menu :: struct($MenuItemCount: int, $Action: typeid) {
	selected: i32,
	font:     rl.Font,
	items:    [MenuItemCount]MenuItem(Action),
}

Winner :: enum {
	Player1,
	Player2,
	Draw,
}

StateGame :: struct {
	game_over: bool,
	winner:    Maybe(Winner),
	kills:     u32,
}

StatePause :: struct {
	menu: Menu(PAUSE_MENU_ITEMS, PauseMenuAction),
}

StateGameOver :: struct {
	winner: Winner,
}

State :: union {
	StateMenu,
	StateOptions,
	StateGame,
	StatePause,
	StateGameOver,
}

when ODIN_DEBUG || ODIN_OS == .JS {
	DebugFields :: struct {
		debug_spawn_enemy: bool,
	}
} else {
	DebugFields :: struct {
	}
}

GameObject :: struct {
	players:                 [2]Player,
	states:                  fa.Fixed_Dynamic_Array(State),
	operators:               ea.Operator_Map,
	cameras:                 [2]rl.Camera2D,
	screen_textures:         [2]rl.RenderTexture,
	weighted_upgrade_types:  fa.Fixed_Dynamic_Array(UpgradeType),
	assets:                  map[string]TextureContainer,
	scaling:                 map[string]ea.Expression_Block,
	player_appearance:       [2]Appearance,
	enemy_appearance:        Appearance,
	health_pack_appearance:  Appearance,
	xp_appearance:           Appearance,
	background:              rl.Texture,
	debug_flags:             DebugFlags,
	settings:                UserSettings,
	running:                 bool,
	screen_width:            i32,
	screen_height:           i32,
	last_screen_width:       i32,
	last_screen_height:      i32,
	player_size:             f32,
	enemy_size:              f32,
	accumulator:             f32,
	zoom:                    f32,
	shader_magic:            rl.Shader,
	shader_magic_resolution: i32,
	shader_magic_time:       i32,
	shader_magic_center:     i32,
	using dbg:               DebugFields,
}

peek_state :: proc() -> (^State, bool) #optional_ok {
	return fa.get_ptr_safe(&g_obj.states, fa.len(g_obj.states) - 1)
}


cast_state :: proc($T: typeid) -> (v: ^T, ok: bool) #optional_ok {
	return &(peek_state() or_return).(T)
}

state :: proc {
	peek_state,
	cast_state,
}

peek_previous_state :: proc() -> (^State, bool) #optional_ok {
	return fa.get_ptr_safe(&g_obj.states, fa.len(g_obj.states) - 2)
}

cast_previous_state :: proc($T: typeid) -> (^T, bool) #optional_ok {
	return &(peek_previous_state()).(T)
}

previous_state :: proc {
	peek_previous_state,
	cast_previous_state,
}

push_state :: proc(state: State) {
	fa.append(&g_obj.states, state)
}

destroy_state :: proc(state: State, ok: bool) {
	switch &s in state {
	case StateGame:
		break
	case StateGameOver:
		break
	case StatePause:
		break
	case StateMenu:
		break
	case StateOptions:
		break
	}
}

@(deferred_out = destroy_state)
pop_state :: proc() -> (State, bool) #optional_ok {
	return fa.pop_back_safe(&g_obj.states)
}

paused :: proc() -> bool {
	_, ok := state(StatePause)
	return ok
}

Projectile :: struct {
	owner:        ^Player,
	damage:       f32,
	using entity: Entity,
}

Pickup :: struct {
	picked_up:    bool,
	xp:           u32,
	hp:           i32,
	using entity: Entity,
}

UpgradeType :: enum {
	NewWeapon,
	MaxHP,
	MovementSpeed,
	LowerCooldown,
	MoreDamage,
	BiggerSize,
	PickupRange,
	XpGain,
}

AmountType :: enum {
	Value,
	Percent,
}

Upgrade :: struct {
	weapon:      Maybe(WeaponType),
	type:        UpgradeType,
	amount:      f32,
	amount_type: AmountType,
}

ExperienceValues :: struct {
	current:             u32,
	needed:              u32,
	level:               u32,
	remaining_level_ups: u32,
}

Stats :: struct {
	max_hp:        Stat(i32),
	xp_multiplier: Stat(f32),
	speed:         Stat(f32),
	pickup_range:  Stat(f32),
}

Player :: struct {
	id:                 int,
	gamepad_id:         i32,
	exp:                ExperienceValues,
	iframes:            u32,
	area:               rl.Rectangle,
	stats:              Stats,
	enemy_rng_seed:     u64,
	item_rng_seed:      u64,
	color:              rl.Color,
	using with_hp:      WithHp,
	using entity:       Entity,
	weapons:            fa.Fixed_Dynamic_Array(Weapon),
	available_upgrades: fa.Fixed_Dynamic_Array(Upgrade),
	enemies:            fa.Fixed_Dynamic_Array(Enemy),
	projectiles:        fa.Fixed_Dynamic_Array(Projectile),
	pickups:            fa.Fixed_Dynamic_Array(Pickup),
	used_upgrades:      fa.Fixed_Dynamic_Array(Upgrade),
}

HurtAnimation :: struct {
	duration:   u32,
	swap_after: u32,
	tick:       u32,
	current:    u32,
	colors:     [2]rl.Color,
}

Animation :: union {
	HurtAnimation,
}

SquareCollisionBox :: struct {
	size:     f32,
	offset_x: f32,
	offset_y: f32,
}

RectangleCollisionBox :: struct {
	width:    f32,
	height:   f32,
	offset_x: f32,
	offset_y: f32,
}

CircleCollisionBox :: struct {
	radius:   f32,
	offset_x: f32,
	offset_y: f32,
}

CollisionBox :: union {
	SquareCollisionBox,
	RectangleCollisionBox,
	CircleCollisionBox,
}

WithHp :: struct {
	hp: i32,
}

Enemy :: struct {
	hit_cooldown:  [WeaponType]u32,
	using with_hp: WithHp,
	using entity:  Entity,
}

Entity :: struct {
	position:       Vec2,
	velocity:       Vec2,
	appearance:     Appearance,
	dampening:      f32,
	last_direction: Vec2,
}

Controls :: struct {
	up:      rl.KeyboardKey `json:"up"`,
	down:    rl.KeyboardKey `json:"down"`,
	left:    rl.KeyboardKey `json:"left"`,
	right:   rl.KeyboardKey `json:"right"`,
	upgrade: [4]rl.KeyboardKey `json:"pick_upgrade"`,
}

handle_input_in_game :: proc(player: ^Player) {
	p_keys := g_obj.settings.key_bindings[player.id]
	direction := Vec2{0, 0}
	if rl.IsKeyDown(p_keys.down) {
		direction.y += 1
	}
	if rl.IsKeyDown(p_keys.up) {
		direction.y -= 1
	}
	if rl.IsKeyDown(p_keys.right) {
		direction.x += 1
	}
	if rl.IsKeyDown(p_keys.left) {
		direction.x -= 1
	}

	if rl.IsGamepadAvailable(player.gamepad_id) {
		if rl.IsGamepadButtonPressed(player.gamepad_id, rl.GamepadButton.LEFT_FACE_DOWN) {
			direction.y += 1
		}
		if rl.IsGamepadButtonPressed(player.gamepad_id, rl.GamepadButton.LEFT_FACE_UP) {
			direction.y -= 1
		}
		if rl.IsGamepadButtonPressed(player.gamepad_id, rl.GamepadButton.LEFT_FACE_LEFT) {
			direction.x -= 1
		}
		if rl.IsGamepadButtonPressed(player.gamepad_id, rl.GamepadButton.LEFT_FACE_RIGHT) {
			direction.x += 1
		}
		direction.x += rl.GetGamepadAxisMovement(player.gamepad_id, rl.GamepadAxis.LEFT_X)
		direction.y -= rl.GetGamepadAxisMovement(player.gamepad_id, rl.GamepadAxis.LEFT_Y)
	}

	direction = rl.Vector2Normalize(direction)

	p_entity := &player.entity
	p_entity.velocity = direction * player.stats.speed.value * g_conf.physics.units.speed

	if p_entity.velocity.x > 0.01 {
		p_entity.last_direction.x = 1
	} else if p_entity.velocity.x < -0.01 {
		p_entity.last_direction.x = -1
	}
}

/// A basic logistic "step" centered at x=0, sharpened by factor k.
logistic :: proc(x: f64, k: f64) -> f64 {
	return 1.0 / (1.0 + math.exp_f64(-k * x))
}

/// A basic approximation of XP to next level, based on a logistic function.
///   - A linear baseline (16*(L - 1))
///   - One smooth jump near L=20
///   - Another smooth jump near L=40
calculate_xp_needed :: proc(level: f64) -> f64 {
	// Tune these to adjust your curve:
	k := 3.0 // how steep the logistic transitions are
	jump1 := 500.0 // jump size near level 20
	jump2 := 350.0 // jump size near level 40

	baseline := 16.0 * (level - 1.0)
	jump_near_20 := jump1 * logistic(level - 20.0, k)
	jump_near_40 := jump2 * logistic(level - 40.0, k)

	return baseline + jump_near_20 + jump_near_40
}

increase :: proc(base: f32, upgrade: Upgrade) -> (new_value: f32) {
	switch upgrade.amount_type {
	case .Percent:
		new_value = base * (1.0 + upgrade.amount)
	case .Value:
		new_value = base + upgrade.amount
	}
	return
}

decrease :: proc(base: f32, upgrade: Upgrade) -> (new_value: f32) {
	switch upgrade.amount_type {
	case .Percent:
		new_value = base * (1.0 - upgrade.amount)
	case .Value:
		new_value = base - upgrade.amount
	}
	return
}

apply_upgrades :: proc(player: ^Player) {
	for &w in slice(&player.weapons) {
		area := w.area.base
		cooldown := w.cooldown.base
		damage := w.damage.base

		for &upgrade in slice(&player.used_upgrades) {
			weapon := upgrade.weapon
			if weapon == nil || w.type == weapon {
				#partial switch upgrade.type {
				case .LowerCooldown:
					cooldown = decrease(cooldown, upgrade)
				case .MoreDamage:
					damage = increase(damage, upgrade)
				case .BiggerSize:
					area = increase(area, upgrade)
				}
			}
		}

		w.area.value = area
		w.cooldown.value = cooldown
		w.damage.value = damage
	}

	speed := player.stats.speed.base
	max_hp := f32(player.stats.max_hp.base)
	pickup_range := player.stats.pickup_range.base
	xp_multiplier := player.stats.xp_multiplier.base
	for &upgrade in slice(&player.used_upgrades) {
		#partial switch upgrade.type {
		case .MaxHP:
			max_hp = increase(max_hp, upgrade)
		case .MovementSpeed:
			speed = increase(speed, upgrade)
		case .PickupRange:
			pickup_range = increase(pickup_range, upgrade)
		case .XpGain:
			xp_multiplier = increase(xp_multiplier, upgrade)
		}
	}
	player.stats.xp_multiplier.value = xp_multiplier
	player.stats.pickup_range.value = pickup_range
	player.stats.speed.value = speed
	player.stats.max_hp.value = i32(max_hp)
}

weapon_count :: proc(player: Player) -> int {
	return fa.len(player.weapons)
}

upgrade_already_present :: proc(upgrades: []Upgrade, weapon: WeaponType) -> bool {
	for upgrade in upgrades {
		#partial switch upgrade.type {
		case .NewWeapon:
			if upgrade.weapon == weapon {
				return true
			}
		}
	}
	return false
}

weapon_already_equipped :: proc(equipped: []Weapon, weapon: WeaponType) -> bool {
	for w in equipped {
		if w.type == weapon {
			return true
		}
	}
	return false
}

random_increase :: proc(upgrade_type: UpgradeType) -> (amount: f32, amount_type: AmountType) {
	cfg := g_conf.balancing.upgrades.per_type[upgrade_type]
	range: Range
	chance_for_percent_upgrade: f32

	chance_for_percent_upgrade =
		cfg.chance_for_percent_upgrade.? or_else g_conf.balancing.upgrades.general.chance_for_percent_upgrade

	if rand.float32() <= chance_for_percent_upgrade {
		amount_type = AmountType.Percent
		range = cfg.percent.? or_else g_conf.balancing.upgrades.general.percent
	} else {
		amount_type = AmountType.Value
		range = cfg.flat.? or_else g_conf.balancing.upgrades.general.flat
	}

	amount = rand.float32_range(range.min, range.max)
	return
}

is_player_upgrade :: proc(upgrade_type: UpgradeType) -> (is_player_upgrade: bool) {
	switch upgrade_type {
	case .MaxHP, .MovementSpeed, .PickupRange, .XpGain:
		is_player_upgrade = true
	case .MoreDamage, .BiggerSize, .LowerCooldown, .NewWeapon:
		is_player_upgrade = false
	}
	return
}

generate_non_weapon_upgrade :: proc(
	player: ^Player,
	weapon: Maybe(WeaponType),
	upgrade_type: Maybe(UpgradeType),
) -> Upgrade {
	weapon := weapon
	for weapon != nil {
		for_weapon := rand.float32() >= 0.5
		weapon = nil if !for_weapon else rand.choice(slice(&player.weapons)).type
	}

	upgrade_type :=
		upgrade_type.? if upgrade_type != nil else rand.choice(slice(&g_obj.weighted_upgrade_types))
	for upgrade_type == .NewWeapon {
		upgrade_type = rand.choice(slice(&g_obj.weighted_upgrade_types))
	}

	if is_player_upgrade(upgrade_type) {
		weapon = nil
	}

	amount, amount_type := random_increase(upgrade_type)
	return Upgrade{weapon, upgrade_type, amount, amount_type}
}

generate_upgrades :: proc(player: ^Player, upgrades_wanted: int) {
	next := rand.uint64()
	rand.reset(player.item_rng_seed)
	for fa.len(player.available_upgrades) < upgrades_wanted {
		if weapon_count(player^) <= g_conf.balancing.player.weapon_count {
			upgrade_type := rand.choice(slice(&g_obj.weighted_upgrade_types))
			weapon: Maybe(WeaponType)
			if rand.float32() >= 0.5 {
				weapon = rand.choice(ALL_UPGRADE_WEAPONS)
			}
			#partial switch upgrade_type {
			case .NewWeapon:
				if weapon == nil ||
				   weapon_already_equipped(slice(&player.weapons), weapon.?) ||
				   upgrade_already_present(slice(&player.available_upgrades), weapon.?) {
					continue
				}
				fa.append(&player.available_upgrades, Upgrade{weapon, .NewWeapon, 0, .Percent})
			case:
				fa.append(
					&player.available_upgrades,
					generate_non_weapon_upgrade(player, weapon, upgrade_type),
				)
			}
		} else {
			fa.append(&player.available_upgrades, generate_non_weapon_upgrade(player, nil, nil))
		}
	}
	player.item_rng_seed = rand.uint64()
	rand.reset(next)
}

increase_to_string :: proc(amount: f32, amount_type: AmountType) -> cstring {
	switch amount_type {
	case .Percent:
		return fmt.ctprintf("%d%%", int(amount * 100))
	case .Value:
		return fmt.ctprintf("%d", int(amount))
	}
	unreachable()
}

get_weapon_name :: proc(weapon: Maybe(WeaponType)) -> cstring {
	if weapon == nil {
		return ""
	}

	#partial switch weapon.? {
	case WeaponType.Projectile:
		return "Projectile"
	case WeaponType.Zone:
		return "Zone"
	}
	return "UNKNOWN"
}

get_weapon_name_for_upgrade :: proc(weapon: Maybe(WeaponType)) -> cstring {
	return "" if weapon == nil else fmt.ctprintf(" for %s", get_weapon_name(weapon.?))
}

handle_global_input :: proc() {
	if rl.IsKeyPressed(kb.F11) {
		rl.ToggleBorderlessWindowed()
	}

	when ODIN_DEBUG || ODIN_OS == .JS {
		if .DebugMode in g_obj.debug_flags {
			mwheel := rl.GetMouseWheelMoveV()
			g_obj.zoom += mwheel.y * 0.1
			g_obj.zoom = math.clamp(g_obj.zoom, 0.1, 4.0)

			if rl.IsKeyPressed(kb.R) {
				g_obj.zoom = g_conf.general.zoom
			}

			if rl.IsKeyDown(kb.LEFT_CONTROL) &&
			   rl.IsKeyDown(kb.LEFT_ALT) &&
			   rl.IsKeyPressed(kb.G) {
				g_obj.debug_flags ~= {.GodMode}
			}

			if rl.IsKeyDown(kb.LEFT_CONTROL) &&
			   rl.IsKeyDown(kb.LEFT_ALT) &&
			   rl.IsKeyPressed(kb.F) {
				g_obj.debug_flags ~= {.RenderGridText}
			}
		} else {
			g_obj.zoom = g_conf.general.zoom
		}

		if rl.IsKeyDown(kb.LEFT_CONTROL) &&
		   rl.IsKeyDown(kb.LEFT_ALT) &&
		   rl.IsKeyPressed(kb.PERIOD) {
			g_obj.debug_flags ~= {.DebugMode}
			if .DebugMode in g_obj.debug_flags {
				rl.SetWindowTitle(WINDOW_TITLE_DEBUG)
			} else {
				rl.SetWindowTitle(WINDOW_TITLE)
				g_obj.debug_flags = {}
			}
		}
	}
}

handle_menu :: proc(
	$MenuItemCount: int,
	$Action: typeid,
	menu: ^Menu(MenuItemCount, Action),
) -> Maybe(Action) {
	if rl.IsKeyPressed(kb.DOWN) || rl.IsKeyPressed(kb.S) {
		menu.selected += 1
	} else if rl.IsKeyPressed(kb.UP) || rl.IsKeyPressed(kb.W) {
		menu.selected -= 1
	}

	for i in 0 ..< 2 {
		gp := i32(i)
		if rl.IsGamepadAvailable(gp) {
			if rl.IsGamepadButtonPressed(gp, rl.GamepadButton.LEFT_FACE_DOWN) {
				menu.selected += 1
			} else if rl.IsGamepadButtonPressed(gp, rl.GamepadButton.LEFT_FACE_UP) {
				menu.selected -= 1
			}

			axis := rl.GetGamepadAxisMovement(gp, rl.GamepadAxis.LEFT_Y)
			if axis > 0.5 {
				menu.selected += 1
			} else if axis < -0.5 {
				menu.selected -= 1
			}
		}
	}

	menu.selected %%= len(menu.items)

	accepted := false
	if rl.IsKeyPressed(kb.SPACE) || rl.IsKeyPressed(kb.ENTER) {
		accepted = true
	}

	if rl.IsGamepadAvailable(0) {
		if rl.IsGamepadButtonPressed(0, rl.GamepadButton.RIGHT_FACE_DOWN) {
			accepted = true
		}
	}
	if accepted {
		return menu.items[menu.selected].action
	}
	return nil
}

handle_input_menu :: proc(menu_state: ^StateMenu) {
	when ODIN_OS != .JS {
		if rl.IsKeyPressed(kb.ESCAPE) {
			g_obj.running = false
		}
	}

	action := handle_menu(MAIN_MENU_ITEMS, MainMenuAction, &menu_state.menu)
	if action == nil {
		action = handle_menu_mouse(MAIN_MENU_ITEMS, MainMenuAction, &menu_state.menu, 0, 0)
	}
	if action == nil {
		return
	}
	switch action.? {
	case .Play:
		start_game()
	case .Options:
	// push_state(StateOptions{})
	case .Exit:
		g_obj.running = false
	}
}

toggle_gamepad :: proc(game: ^StateGame, player_id: int) {
	if g_obj.players[player_id].gamepad_id == -1 {
		for i in 0 ..< 2 {
			gp := i32(i)
			if g_obj.players[1 - player_id].gamepad_id != gp && rl.IsGamepadAvailable(gp) {
				g_obj.players[player_id].gamepad_id = gp
				return
			}
		}
	} else {
		g_obj.players[player_id].gamepad_id = -1
	}
}

handle_input_game :: proc(game: ^StateGame) {
	pause_requested := false
	if rl.IsKeyPressed(kb.ESCAPE) {
		pause_requested = true
	}

	if rl.IsKeyPressed(kb.F1) {
		toggle_gamepad(game, 0)
	}

	if rl.IsKeyPressed(kb.F2) {
		toggle_gamepad(game, 1)
	}

	for player in g_obj.players {
		if rl.IsGamepadAvailable(player.gamepad_id) {
			if rl.IsGamepadButtonPressed(player.gamepad_id, rl.GamepadButton.MIDDLE_RIGHT) {
				pause_requested = true
			}
		}
	}

	if pause_requested {
		menu: [PAUSE_MENU_ITEMS]MenuItem(PauseMenuAction)

		when ODIN_OS == .JS {
			menu = {{"Resume", .Resume}, {"Back to menu", .ToMainMenu}}
		} else {
			menu = {{"Resume", .Resume}, {"Back to menu", .ToMainMenu}, {"Exit", .Exit}}
		}
		push_state(StatePause{{0, rl.GetFontDefault(), menu}})
	}

	when ODIN_DEBUG || ODIN_OS == .JS {
		g_obj.debug_spawn_enemy = false
		if .DebugMode in g_obj.debug_flags {
			if !rl.IsKeyDown(kb.LEFT_CONTROL) &&
			   !rl.IsKeyDown(kb.LEFT_ALT) &&
			   rl.IsKeyPressed(kb.PERIOD) {
				g_obj.debug_spawn_enemy = true
			}
			if rl.IsKeyPressed(kb.F7) {
				g_obj.debug_flags ~= {.PlayerShowCollisionBoxes}
			}
			if rl.IsKeyPressed(kb.F8) {
				g_obj.debug_flags ~= {.EnemyShowCollisionBoxes}
			}
			if rl.IsKeyPressed(kb.F9) {
				g_obj.debug_flags ~= {.ProjectileShowCollisionBoxes}
			}
			if rl.IsKeyPressed(kb.F10) {
				col_count := card(
					DebugFlags {
						.PlayerShowCollisionBoxes,
						.EnemyShowCollisionBoxes,
						.ProjectileShowCollisionBoxes,
					} &
					g_obj.debug_flags,
				)
				if col_count == 0 {
					g_obj.debug_flags += {
						.PlayerShowCollisionBoxes,
						.EnemyShowCollisionBoxes,
						.ProjectileShowCollisionBoxes,
					}
				} else {
					g_obj.debug_flags -= {
						.PlayerShowCollisionBoxes,
						.EnemyShowCollisionBoxes,
						.ProjectileShowCollisionBoxes,
					}
				}
			}
		}
	}

	for &player in g_obj.players {
		handle_input_in_game(&player)
	}
}

calculate_new_seed :: proc($T1: typeid, v1: T1, $T2: typeid, v2: T2) -> u64 {
	bytes := make([]u8, size_of(T1) + size_of(T2) + 4)
	defer delete(bytes)
	last_index := 0
	a1 := transmute([size_of(T1)]u8)v1
	for v in a1 {
		bytes[last_index] = v
		last_index += 1
	}
	rand_bytes := transmute([4]u8)rand.uint32()
	for b in rand_bytes {
		bytes[last_index] = b
		last_index += 1
	}
	a2 := transmute([size_of(T2)]u8)v2
	for v in a2 {
		bytes[last_index] = v
		last_index += 1
	}
	digest := hash.hash_bytes(hash.Algorithm.SHA256, bytes)
	defer delete(digest)
	new_seed := [8]u8 {
		digest[1],
		digest[2],
		digest[3],
		digest[4],
		digest[4],
		digest[3],
		digest[2],
		digest[1],
	}
	return transmute(u64)new_seed
}

id_to_button :: proc(id: int) -> rl.GamepadButton {
	switch id {
	case 0:
		return rl.GamepadButton.RIGHT_FACE_LEFT
	case 1:
		return rl.GamepadButton.RIGHT_FACE_UP
	case 2:
		return rl.GamepadButton.RIGHT_FACE_RIGHT
	}
	return rl.GamepadButton.RIGHT_FACE_DOWN
}

get_entity_size :: proc(entity: ^Entity) -> (size: Vec2) {
	switch cb in entity.appearance.bbox {
	case SquareCollisionBox:
		size = {cb.size, cb.size}
	case RectangleCollisionBox:
		size = {cb.width, cb.height}
	case CircleCollisionBox:
		size = {cb.radius, cb.radius}
	}
	return
}

clamp_entity_to_area :: proc(entity: ^Entity, area: rl.Rectangle) {
	entity_size := get_entity_size(entity)
	half_width := (entity_size.x / 2)
	half_height := (entity_size.y / 2)
	if entity.position.x > area.x + area.width - half_width {
		entity.position.x = area.x + area.width - half_width
	}
	if entity.position.x < area.x + half_width {
		entity.position.x = area.x + half_width
	}
	if entity.position.y > area.y + area.height - half_height {
		entity.position.y = area.y + area.height - half_height
	}
	if entity.position.y < area.y + half_height {
		entity.position.y = area.y + half_height
	}
}

update_game :: proc(game: ^StateGame, dt: f32) {
	for &player in g_obj.players {
		p_entity := &player.entity

		if player.iframes > 0 {
			player.iframes -= 1
		}

		for &enemy in slice(&player.enemies) {
			move_towards(&enemy, p_entity)
			if enemy.velocity.x > 0.01 {
				enemy.last_direction.x = 1
			} else if enemy.velocity.x < -0.01 {
				enemy.last_direction.x = -1
			}
			enemy.position += enemy.velocity * dt
		}

		for &pickup in slice(&player.pickups) {
			if pickup.picked_up {
				col, _ := get_collision(&pickup.entity, p_entity)
				pickup.entity.velocity =
					col.direction *
					g_conf.balancing.pickup.follow_speed *
					g_conf.physics.units.speed
			}
			pickup.entity.position += pickup.entity.velocity * dt
		}

		handle_collisions(game, &player)
		if game.game_over {
			continue
		}

		if player.exp.current >= player.exp.needed {
			player.exp.current -= player.exp.needed
			player.exp.level += 1
			player.exp.needed = u32(calculate_xp_needed(f64(player.exp.level + 1)))
			player.exp.remaining_level_ups += 1
		}

		if player.exp.remaining_level_ups > 0 && fa.len(player.available_upgrades) == 0 {
			player.exp.remaining_level_ups -= 1
			generate_upgrades(&player, g_conf.balancing.player.upgrade_count)
		}

		if fa.len(player.available_upgrades) > 0 {
			was_pressed := false
			for uk, i in g_obj.settings.key_bindings[player.id].upgrade {
				if rl.IsKeyPressed(uk) {
					was_pressed = true
				}

				if rl.IsGamepadAvailable(player.gamepad_id) {
					if rl.IsGamepadButtonPressed(player.gamepad_id, id_to_button(i)) {
						was_pressed = true
					}
				}

				if was_pressed {
					upgrade := fa.get(player.available_upgrades, i)
					weapon := upgrade.weapon
					#partial switch upgrade.type {
					case .NewWeapon:
						if weapon_count(player) <= g_conf.balancing.player.weapon_count {
							assert(weapon != nil)
							weapon := weapon.?
							fa.append(&player.weapons, make_weapon(weapon))
						}
					case:
						fa.append(&player.used_upgrades, upgrade)
					}
					fa.clear(&player.available_upgrades)

					rand.reset(player.item_rng_seed)
					player.item_rng_seed = calculate_new_seed(int, i, int, i)
					break
				}
			}
			if was_pressed {
				apply_upgrades(&player)
			}
		}

		it := fa_iter.make_sync_iter(&player.projectiles)
		for projectile in fa_iter.next_ref(&it) {
			projectile.entity.position += projectile.entity.velocity * dt
			if projectile.entity.position.x < player.area.x ||
			   projectile.entity.position.x > player.area.x + player.area.width ||
			   projectile.entity.position.y < player.area.y ||
			   projectile.entity.position.y > player.area.y + player.area.height {
				fa.unordered_remove(&player.projectiles, projectile)
				continue
			}
			it := fa_iter.make_sync_iter(&player.enemies)
			for enemy in fa_iter.next_ref(&it) {
				// TODO: Fix collision detection and use it here.
				// ! This is basically a hack to make it work for now
				colliding := false
				distance := magnitude(projectile.entity.position - enemy.position)
				max_size :=
					get_max_size(projectile.entity.appearance.bbox) / 2 + g_obj.enemy_size / 2
				if distance <= max_size {
					colliding = true
				}
				if colliding {
					hit_enemy(game, projectile.owner, enemy, projectile.damage)
					if game.game_over {
						break
					}
					fa.unordered_remove(&player.projectiles, projectile)
					break
				}
			}

			if game.game_over {
				break
			}
		}

		if game.game_over {
			continue
		}

		p_entity.position += p_entity.velocity * (1 - p_entity.dampening) * dt

		p_area := player.area
		clamp_entity_to_area(p_entity, p_area)

		handle_weapons(game, &player)

		when ODIN_DEBUG || ODIN_OS == .JS {
			if g_obj.debug_spawn_enemy {
				_ = spawn_enemies(&player, g_conf.balancing.enemy.spawn_safe_zone, 1, game.kills)
			}
		}
	}
}

EntityStatus :: enum {
	Dead,
	Alive,
}

move_towards :: proc(entity: ^Entity, target: ^Entity) {
	if .EnemyFreeze in g_obj.debug_flags {
		return
	}
	col, _ := get_collision(entity, target)

	speed, err := ea.eval_expr(g_obj.scaling["enemy_speed"], g_conf.variables, g_obj.operators)

	if err != nil {
		panic(fmt.tprint(err))
	}

	entity.velocity = col.direction * speed * g_conf.physics.units.speed
}

damage_entity :: proc(entity: ^WithHp, damage: f32) -> EntityStatus {
	if .EnemyGodMode in g_obj.debug_flags {
		return get_entity_status(entity^)
	}

	entity.hp -= i32(damage)
	return get_entity_status(entity^)
}

get_max_size :: proc(collision_box: CollisionBox) -> f32 {
	switch cb in collision_box {
	case SquareCollisionBox:
		return math.sqrt(math.pow(cb.size, 2) + math.pow(cb.size, 2))
	case RectangleCollisionBox:
		return math.sqrt(math.pow(cb.width, 2) + math.pow(cb.height, 2))
	case CircleCollisionBox:
		return cb.radius * 2
	}
	return 0
}

get_min_size :: proc(collision_box: CollisionBox) -> f32 {
	switch cb in collision_box {
	case SquareCollisionBox:
		return cb.size
	case RectangleCollisionBox:
		return min(cb.width, cb.height)
	case CircleCollisionBox:
		return cb.radius
	}
	return 0
}

start_game :: proc() {
	g_obj.accumulator = 0
	seed := rand.uint64()
	for &player in g_obj.players {
		reset_player(&player, seed)
	}
	push_state(StateGame{game_over = false, winner = nil})
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	for _, &v in g_obj.assets {
		rl.UnloadTexture(v.texture)
	}
	rl.UnloadTexture(g_obj.background)
	rl.UnloadShader(g_obj.shader_magic)

	for pa in g_obj.player_appearance {
		if t, ok := pa.type.(TextureContainer); ok {
			rl.UnloadTexture(t.texture)
		}
	}
	if t, ok := g_obj.enemy_appearance.type.(TextureContainer); ok {
		rl.UnloadTexture(t.texture)
	}
	if t, ok := g_obj.health_pack_appearance.type.(TextureContainer); ok {
		rl.UnloadTexture(t.texture)
	}
	if t, ok := g_obj.xp_appearance.type.(TextureContainer); ok {
		rl.UnloadTexture(t.texture)
	}

	// De-Initialization
	//--------------------------------------------------------------------------------------
	for &screen_texture in g_obj.screen_textures {
		rl.UnloadRenderTexture(screen_texture)
	}

	rl.CloseWindow()

	for &player in g_obj.players {
		if v, ok := player.entity.appearance.type.(TextureContainer); ok {
			rl.UnloadTexture(v.texture)
		}
		for &enemy in slice(&player.enemies) {
			if v, ok := enemy.entity.appearance.type.(TextureContainer); ok {
				rl.UnloadTexture(v.texture)
			}
		}
		for &projectile in slice(&player.projectiles) {
			if v, ok := projectile.entity.appearance.type.(TextureContainer); ok {
				rl.UnloadTexture(v.texture)
			}
		}
		for &pickup in slice(&player.pickups) {
			if v, ok := pickup.entity.appearance.type.(TextureContainer); ok {
				rl.UnloadTexture(v.texture)
			}
		}
	}

	when #config(PRINT_PEAK_MEMORY_USAGE, false) {
		fmt.printfln("PEAK ALLOCATION SIZE (RUNTIME): %v bytes", arena.peak_used)
	}

	mem.free_all(allocator)
	delete(memory)
	mem.free_all(context.temp_allocator)
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			g_obj.running = false
		}
	}

	return g_obj.running
}

handle_pause_input :: proc(pause: ^StatePause) {
	if rl.IsKeyPressed(kb.ESCAPE) {
		pop_state()
	}
	action := handle_menu(PAUSE_MENU_ITEMS, PauseMenuAction, &pause.menu)
	if action == nil {
		action = handle_menu_mouse(
			PAUSE_MENU_ITEMS,
			PauseMenuAction,
			&pause.menu,
			0,
			f32(g_obj.screen_height) / 4,
		)
	}
	if action == nil {
		return
	}
	switch action.? {
	case .Resume:
		pop_state()
	case .ToMainMenu:
		pop_state()
		pop_state()
	case .Exit:
		g_obj.running = false
	}
}

MenuMeasurements :: struct {
	left_most:   f32,
	text_height: f32,
	text_width:  f32,
}

MenuItemBounds :: struct {
	text_position: Vec2,
	rect:          rl.Rectangle,
}

get_menu_item_bounds :: proc(
	measurements: MenuMeasurements,
	offset_x: f32,
	offset_y: f32,
	menu_padding: f32,
	menu_index: int,
) -> MenuItemBounds {
	left_most := measurements.left_most
	text_width := measurements.text_width
	text_height := measurements.text_height

	text_x := offset_x + (f32(g_obj.screen_width) - text_width) / 2
	text_y := offset_y + (text_height + menu_padding) * (f32(menu_index) + 2)

	return {{text_x, text_y}, {left_most - 10, text_y - 10, text_width + 20, text_height + 20}}
}

get_menu_measurements :: proc(
	$MenuItemCount: int,
	$Action: typeid,
	menu: ^Menu(MenuItemCount, Action),
	font_size: f32,
	font_spacing: f32,
) -> MenuMeasurements {
	left_most := f32(g_obj.screen_width)
	text_height: f32 = 0
	text_width: f32 = 0

	for item in menu.items {
		text_size := rl.MeasureTextEx(menu.font, item.text, font_size, font_spacing)
		if text_size.y > text_height {
			text_height = text_size.y
		}
		if text_size.x > text_width {
			text_width = text_size.x
		}
		text_x := (f32(g_obj.screen_width) - text_size.x) / 2
		if text_x < left_most {
			left_most = text_x
		}
	}
	return MenuMeasurements{left_most, text_height, text_width}
}

handle_menu_mouse :: proc(
	$MenuItemCount: int,
	$Action: typeid,
	menu: ^Menu(MenuItemCount, Action),
	offset_x: f32,
	offset_y: f32,
) -> Maybe(Action) {
	if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		mouse_pos := rl.GetMousePosition()

		for _, i in menu.items {
			bounds := get_menu_item_bounds(
				get_menu_measurements(
					MenuItemCount,
					Action,
					menu,
					MENU_FONT_SIZE,
					MENU_FONT_SPACING,
				),
				offset_x,
				offset_y,
				MENU_PADDING,
				i,
			)

			if rl.CheckCollisionPointRec(mouse_pos, bounds.rect) {
				return menu.items[i].action
			}
		}
	}
	return nil
}

set_shader_time :: proc(shader: rl.Shader, time_loc: i32, time: f64) {
	time := time
	rl.SetShaderValue(shader, time_loc, &time, .FLOAT)
}

set_shader_times :: proc() {
	time := rl.GetTime()
	set_shader_time(g_obj.shader_magic, g_obj.shader_magic_time, time)
}

update :: proc() {
	// Update
	//----------------------------------------------------------------------------------

	handle_global_input()

	// Get the current screen size to handle window resizing
	g_obj.screen_width, g_obj.screen_height = get_screen_size()

	#partial switch _ in state() {
	case StateGameOver:
		confirmed := false
		if rl.IsKeyPressed(kb.ESCAPE) ||
		   rl.IsKeyPressed(kb.ENTER) ||
		   rl.IsKeyPressed(kb.SPACE) ||
		   rl.IsMouseButtonPressed(.LEFT) {
			confirmed = true
		}

		for i in 0 ..< 2 {
			gp := i32(i)
			if rl.IsGamepadAvailable(gp) {
				if rl.IsGamepadButtonPressed(gp, rl.GamepadButton.RIGHT_FACE_DOWN) ||
				   rl.IsGamepadButtonPressed(gp, rl.GamepadButton.MIDDLE_RIGHT) {
					confirmed = true
				}
			}
		}

		if confirmed {
			pop_state()
		}
	case StatePause:
		pause := state(StatePause)
		handle_pause_input(pause)
	case StateMenu:
		menu := state(StateMenu)
		handle_input_menu(menu)
	case StateGame:
		game := state(StateGame)
		handle_input_game(game)

		// Calculate dt (Delta Time)
		dt := rl.GetFrameTime()

		when ODIN_DEBUG {
			// limit how much time can pass between frames
			// this is to prevent the game from running too fast if
			// the game is being debugged for a long time
			if dt > 2 * (SECONDS_PER_FRAME * f32(FPS)) {
				dt = SECONDS_PER_FRAME
			}
		}

		set_shader_times()

		when ODIN_DEBUG || ODIN_OS == .JS {
			if .DebugMode in g_obj.debug_flags {
				if rl.IsKeyDown(kb.SPACE) &&
				   rl.IsKeyDown(kb.LEFT_SHIFT) &&
				   rl.IsKeyDown(kb.LEFT_CONTROL) {
					dt *= 15.0
				} else if rl.IsKeyDown(kb.SPACE) && rl.IsKeyDown(kb.LEFT_SHIFT) {
					dt *= 10.0
				} else if rl.IsKeyDown(kb.SPACE) {
					dt *= 5.0
				} else if rl.IsKeyDown(kb.LEFT_SHIFT) {
					dt *= (1.0 / 5.0)
				}
			}
		}

		g_obj.accumulator += dt
		for g_obj.accumulator >= SECONDS_PER_FRAME {
			g_obj.accumulator -= SECONDS_PER_FRAME

			update_game(game, SECONDS_PER_FRAME)

			if game.game_over {
				last_game := pop_state().(StateGame)
				log.debugf("Player %v won", last_game.winner.?)
				for &p in g_obj.players {
					log.debugf("Player %v: HP: %v, Enemies: %v", p.id, p.hp, fa.len(p.enemies))
				}

				push_state(StateGameOver{last_game.winner.?})
				break
			}
		}
	}
}

game_loop :: proc() {
	old_context := context
	defer context = old_context
	context.allocator = allocator
	region := mem.begin_arena_temp_memory(&arena)
	defer mem.end_arena_temp_memory(region)
	update()
	draw()
	free_all(context.temp_allocator)
}

is_in_menu :: proc() -> bool {
	#partial switch _ in state() {
	case StateMenu, StatePause, StateGameOver:
		return true
	}
	return false
}
