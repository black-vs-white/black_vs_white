package game

import "core:fmt"
import fa "sol:fixed_dynamic_array"
import rl "vendor:raylib"

// workaround to keep odin from complaining about an unused import
// without having to disabling the check entirely
// this makes it easier to add and remove logging without having to worry about the import
// every time
import "core:log"
_ :: log

draw_area_background :: proc(player: ^Player, visible_area: rl.Rectangle) {
	color: rl.Color
	color.rgb, color.a = rl.WHITE.rgb - player.color.rgb, rl.WHITE.a

	other := player.color
	lerp: f32 = 0.3
	if player.id == 1 {
		lerp = 0.2
	}
	for x in 0 ..< i32(player.area.width / f32(g_obj.background.width)) {
		for y in 0 ..< i32(player.area.height / f32(g_obj.background.height)) {
			rl.DrawTextureEx(
				g_obj.background,
				Vec2 {
					player.area.x + f32(x * g_obj.background.width),
					player.area.y + f32(y * g_obj.background.height),
				},
				0,
				1,
				rl.ColorLerp(color, other, lerp),
			)
		}
	}

	when ODIN_DEBUG || ODIN_OS == .JS {
		if g_obj.debug_flags >= {.RenderGrid} {
			draw_grid(player.area, visible_area)
		}
		if g_obj.debug_flags >= {.RenderGridText} {
			draw_grid_text(player.area, visible_area)
		}
	}
}

draw_grid :: proc(player_area: rl.Rectangle, visible_area: rl.Rectangle) {
	x_unit := i32(player_area.width / g_obj.player_size)
	x_overdraw := (i32((f32(g_obj.screen_width) / 4)) / x_unit)
	// Draw full scene with grid lines
	for i in -x_overdraw ..= i32(player_area.width / g_obj.player_size) + x_overdraw {
		x := player_area.x + g_obj.player_size * f32(i)
		if x < visible_area.x || x > visible_area.x + visible_area.width {
			continue
		}
		rl.DrawLineV(
			Vec2{x, visible_area.y},
			Vec2{x, visible_area.y + visible_area.height},
			rl.LIGHTGRAY,
		)
	}
	y_unit := i32(player_area.height / g_obj.player_size)
	y_overdraw := (i32((f32(g_obj.screen_height) / 2)) / y_unit)
	for i in -y_overdraw ..= i32(player_area.height / g_obj.player_size) + y_overdraw {
		y := player_area.y + g_obj.player_size * f32(i)
		if y < visible_area.y || y > visible_area.y + visible_area.height {
			continue
		}
		rl.DrawLineV(
			Vec2{visible_area.x, y},
			Vec2{visible_area.x + visible_area.width, y},
			rl.LIGHTGRAY,
		)
	}
}

draw_grid_text :: proc(player_area: rl.Rectangle, visible_area: rl.Rectangle) {
	for i in 0 ..< i32(player_area.width / g_obj.player_size) {
		for j in 0 ..< i32(player_area.height / g_obj.player_size) {
			x := player_area.x + g_obj.player_size * f32(i)
			y := player_area.y + g_obj.player_size * f32(j)
			if !rl.CheckCollisionPointRec({x, y}, visible_area) {
				continue
			}
			rl.DrawText(
				rl.TextFormat("[%d,%d]", i, j),
				i32(x + 10),
				i32(y + 15),
				10,
				rl.Fade(rl.LIGHTGRAY, 0.1),
			)
		}
	}
}

draw_entity :: proc(entity: ^Entity, visible_area: rl.Rectangle, debug_draw_collision_box: bool) {
	if !rl.CheckCollisionPointRec(entity.position, visible_area) {
		return
	}
	color := entity.appearance.color

	#partial switch &a in entity.appearance.animation {
	case HurtAnimation:
		if !paused() {
			a.tick += 1
		}
		if a.tick >= a.swap_after {
			a.current = 1 - a.current
			a.tick = 0
		}

		color = a.colors[a.current]

		if !paused() {
			a.duration -= 1
		}
		if a.duration <= 0 {
			entity.appearance.animation = nil
		}
	}

	switch tos in entity.appearance.type {
	case TextureContainer:
		texture := tos
		position := texture.offset + entity.position - (texture.size / 2)
		flip := (f32(int(entity.last_direction.x >= 0.0)) * 2.0 - 1.0) * -1.0 // gives 1 or -1
		rl.DrawTexturePro(
			texture.texture,
			{0.0, 0.0, texture.size.x * f32(flip), texture.size.y},
			{position.x, position.y, texture.size.x, texture.size.y},
			{},
			0.0,
			color,
		)
	case Circle:
		circle := tos
		rl.DrawCircleV(entity.position, circle.radius, color)
	case ShadowCircle:
		shadow_circle := tos
		rl.DrawCircleV(entity.position, shadow_circle.radius + 1, shadow_circle.shadow_color)
		rl.DrawCircleV(entity.position, shadow_circle.radius, color)
	}

	when ODIN_DEBUG || ODIN_OS == .JS {
		if debug_draw_collision_box {
			draw_collision_box(entity.position, entity.appearance.bbox)
		}

		if .EntityDrawPositions in g_obj.debug_flags {
			rl.DrawCircleV(entity.position, 2, rl.BLACK)
		}
	}
}

draw_enemies :: proc(player: ^Player, visible_area: rl.Rectangle) {
	for &enemy in slice(&player.enemies) {
		draw_entity(&enemy, visible_area, .EnemyShowCollisionBoxes in g_obj.debug_flags)
	}
}

draw_projectiles :: proc(player: ^Player, visible_area: rl.Rectangle) {
	rl.BeginShaderMode(g_obj.shader_magic)
	defer rl.EndShaderMode()
	for &projectile in slice(&player.projectiles) {
		rl.SetShaderValue(
			g_obj.shader_magic,
			g_obj.shader_magic_center,
			&projectile.entity.position,
			.VEC2,
		)
		draw_entity(
			&projectile.entity,
			visible_area,
			.ProjectileShowCollisionBoxes in g_obj.debug_flags,
		)
	}
}

draw_weapons :: proc(player: ^Player) {
	background: rl.Color
	background.rgb, background.a = rl.WHITE.rgb - player.entity.appearance.color.rgb, rl.WHITE.a
	for &weapon in slice(&player.weapons) {
		if weapon.type != WeaponType.Zone {
			continue
		}
		rl.DrawCircleV(
			player.entity.position,
			weapon.area.value * g_conf.physics.units.size,
			rl.ColorAlpha(rl.ColorLerp(rl.ORANGE, background, 0.5), 0.3),
		)
	}
}

draw_pickups :: proc(player: ^Player, visible_area: rl.Rectangle) {
	for &c in slice(&player.pickups) {
		draw_entity(&c.entity, visible_area, false)
	}
}

DrawTinyWizard :: proc(position: Vec2, scale: f32, color: rl.Color) {
	rl.DrawTriangle(
		Vec2{position.x, position.y - 4 * scale},
		Vec2{position.x - 4 * scale, position.y + 4 * scale},
		Vec2{position.x + 4 * scale, position.y + 4 * scale},
		color,
	)
	rl.DrawRectangleV(Vec2{position.x, position.y - 1 * scale}, Vec2{4 * scale, 1 * scale}, color)
	rl.DrawRectangleV(
		Vec2{position.x + 4 * scale, position.y - 4 * scale},
		Vec2{1 * scale, 8 * scale},
		color,
	)
	rl.DrawCircleV(Vec2{position.x, position.y - 2 * scale}, 4, color)
	rl.DrawTriangle(
		Vec2{position.x, position.y - 6 * scale},
		Vec2{position.x - 4 * scale, position.y - 2 * scale},
		Vec2{position.x + 4 * scale, position.y - 2 * scale},
		color,
	)
}

draw_collision_box :: proc(pos: Vec2, col: CollisionBox) {
	color := rl.Fade(rl.GREEN, 0.6)
	switch &c in col {
	case CircleCollisionBox:
		rl.DrawCircleLinesV(pos, c.radius, color)
	case RectangleCollisionBox:
		rl.DrawRectangleLinesEx(
			rl.Rectangle{pos.x - (c.width / 2), pos.y - (c.height / 2), c.width, c.height},
			1,
			color,
		)
	case SquareCollisionBox:
		rl.DrawRectangleLinesEx(
			rl.Rectangle{pos.x - (c.size / 2), pos.y - (c.size / 2), c.size, c.size},
			1,
			color,
		)
	}
}

draw_player :: proc(player: ^Player) {
	p_entity := &player.entity

	draw_entity(p_entity, player.area, .PlayerShowCollisionBoxes in g_obj.debug_flags)
}

draw_game_for_player :: proc(game: ^StateGame, screen_width: i32, screen_height: i32) {
	for &player in g_obj.players {
		visible_area := rl.Rectangle {
			player.entity.position.x - ((f32(screen_width) / 4) + (g_obj.player_size * 4)),
			player.entity.position.y - (f32(screen_height) / 2) + (g_obj.player_size * 4),
			(f32(screen_width) / 2) + (g_obj.player_size * 8),
			f32(screen_height) + (g_obj.player_size * 8),
		}

		draw_area_background(&player, visible_area)
		draw_weapons(&player)
		draw_pickups(&player, visible_area)
		draw_projectiles(&player, visible_area)
		draw_enemies(&player, visible_area)
		draw_player(&player)
	}
}

draw_menu :: proc(
	$MenuItemCount: int,
	$Action: typeid,
	menu: ^Menu(MenuItemCount, Action),
	font_size: f32,
	font_spacing: f32,
	offset_x: f32,
	offset_y: f32,
) {
	m := get_menu_measurements(MenuItemCount, Action, menu, font_size, font_spacing)
	left_most := m.left_most
	text_height := m.text_height

	for item, i in menu.items {
		mb := get_menu_item_bounds(m, offset_x, offset_y, MENU_PADDING, i)

		text_x := mb.text_position.x
		text_y := mb.text_position.y

		rl.DrawRectangleV(
			Vec2{mb.rect.x, mb.rect.y},
			Vec2{mb.rect.width, mb.rect.height},
			rl.ColorLerp(rl.DARKGRAY, rl.BLACK, 0.8),
		)
		rl.DrawRectangleV(
			Vec2{mb.rect.x + 2, mb.rect.y + 2},
			Vec2{mb.rect.width - 4, mb.rect.height - 4},
			rl.ColorLerp(rl.DARKGRAY, rl.BLACK, 0.2),
		)

		draw_text_with_shadow_ex(
			menu.font,
			item.text,
			Vec2{text_x, text_y},
			font_size,
			font_spacing,
			rl.RAYWHITE,
			rl.GRAY,
		)
	}

	indicator_x: f32 = f32(left_most) - 20 + offset_x
	indicator_y: f32 =
		f32(text_height + MENU_PADDING) * (f32(menu.selected) + 2) + (text_height / 2) + offset_y
	rl.DrawTriangle(
		Vec2{indicator_x, indicator_y},
		Vec2{indicator_x - 10, indicator_y - 5},
		Vec2{indicator_x - 10, indicator_y + 5},
		rl.RAYWHITE,
	)
}

draw_pause_menu :: proc(pause: ^StatePause) {
	offset_y := f32(g_obj.screen_height) / 4
	m := get_menu_measurements(
		PAUSE_MENU_ITEMS,
		PauseMenuAction,
		&pause.menu,
		MENU_FONT_SIZE,
		MENU_FONT_SPACING,
	)

	mb_first := get_menu_item_bounds(m, 0, offset_y, MENU_PADDING, 0)
	mb_last := get_menu_item_bounds(m, 0, offset_y, MENU_PADDING, PAUSE_MENU_ITEMS - 1)

	unit_y := (mb_last.rect.y - mb_first.rect.y) / f32(len(pause.menu.items))

	rect_x := (f32(g_obj.screen_width) - m.text_width) / 2
	rect_height := mb_last.rect.y + mb_last.rect.height - mb_first.rect.y
	rl.DrawRectangleV(
		Vec2{rect_x - 40, mb_first.rect.y - unit_y - 20},
		Vec2{m.text_width + 80, rect_height + unit_y + 40},
		rl.BLACK,
	)
	rl.DrawRectangleV(
		Vec2{rect_x - 38, mb_first.rect.y - unit_y - 18},
		Vec2{m.text_width + 76, rect_height + unit_y + 36},
		rl.GRAY,
	)
	menu := &pause.menu
	text_size := rl.MeasureTextEx(menu.font, TEXT_PAUSED, MENU_FONT_SIZE, MENU_FONT_SPACING)
	text_x := (f32(g_obj.screen_width) - text_size.x) / 2
	draw_text_with_shadow_ex(
		menu.font,
		TEXT_PAUSED,
		Vec2{text_x, mb_first.rect.y - unit_y},
		MENU_FONT_SIZE,
		MENU_FONT_SPACING,
		rl.WHITE,
	)
	draw_menu(
		PAUSE_MENU_ITEMS,
		PauseMenuAction,
		menu,
		MENU_FONT_SIZE,
		MENU_FONT_SPACING,
		0,
		f32(g_obj.screen_height) / 4,
	)
}

set_shader_resolutions :: proc() {
	set_shader_resolution(g_obj.shader_magic, g_obj.shader_magic_resolution)
}

draw_game :: proc(game: ^StateGame) {
	// Update render textures if screen size has changed
	if g_obj.last_screen_width != g_obj.screen_width ||
	   g_obj.last_screen_height != g_obj.screen_height {
		for _, i in g_obj.players {
			rl.UnloadRenderTexture(g_obj.screen_textures[i])
			g_obj.screen_textures[i] = rl.LoadRenderTexture(
				g_obj.screen_width / 2,
				g_obj.screen_height,
			)
		}
		set_shader_resolutions()
		g_obj.last_screen_width, g_obj.last_screen_height = g_obj.screen_width, g_obj.screen_height
	}

	// Adjust cameras based on new screen size, maintaining a zoom that fits the area
	for &player, i in g_obj.players {
		g_obj.cameras[i].target = player.entity.position
		g_obj.cameras[i].offset = Vec2{f32(g_obj.screen_width) / 4, f32(g_obj.screen_height) / 2}
		g_obj.cameras[i].zoom = g_obj.zoom
	}
	//----------------------------------------------------------------------------------

	// Draw
	//----------------------------------------------------------------------------------
	for &player in g_obj.players {
		rl.BeginTextureMode(g_obj.screen_textures[player.id])
		defer rl.EndTextureMode()
		rl.ClearBackground(rl.DARKGRAY)
		{
			rl.BeginMode2D(g_obj.cameras[player.id])
			defer rl.EndMode2D()
			draw_game_for_player(game, g_obj.screen_width, g_obj.screen_height)
		}

		draw_hud(game, &player)
	}

	// Draw both views render textures to the screen side by side
	// rl.BeginDrawing()
	// defer rl.EndDrawing()
	// rl.ClearBackground(rl.BLACK)

	for _, i in g_obj.players {
		rl.DrawTextureRec(
			g_obj.screen_textures[i].texture,
			rl.Rectangle {
				0,
				0,
				f32(g_obj.screen_textures[i].texture.width),
				-f32(g_obj.screen_textures[i].texture.height),
			},
			// multiply by i to offset the second camera to the right
			Vec2{f32(i32(i) * g_obj.screen_width) / 2.0, 0},
			rl.WHITE,
		)
	}

	rl.DrawRectangle(g_obj.screen_width / 2 - 2, 0, 4, g_obj.screen_height, rl.DARKGREEN)

	draw_balance_bar(game)
	draw_alpha_warning()
}

draw_text_with_shadow :: proc(
	text: cstring,
	x: i32,
	y: i32,
	size: i32,
	color: rl.Color,
	shadow_color: rl.Color = rl.BLACK,
) {
	rl.DrawText(text, x + 2, y + 2, size, shadow_color)
	rl.DrawText(text, x, y, size, color)
}

draw_text_with_shadow_ex :: proc(
	font: rl.Font,
	text: cstring,
	pos: Vec2,
	font_size: f32,
	spacing: f32,
	color: rl.Color,
	shadow_color: rl.Color = rl.BLACK,
) {
	rl.DrawTextEx(font, text, pos + Vec2{2, 2}, font_size, spacing, shadow_color)
	rl.DrawTextEx(font, text, pos, font_size, spacing, color)
}

button_to_name :: proc(button: rl.GamepadButton) -> string {
	#partial switch button {
	// Gamepad left DPAD up button
	case .LEFT_FACE_UP:
		return "↑"
	// Gamepad left DPAD right button
	case .LEFT_FACE_RIGHT:
		return "→"
	// Gamepad left DPAD down button
	case .LEFT_FACE_DOWN:
		return "↓"
	// Gamepad left DPAD left button
	case .LEFT_FACE_LEFT:
		return "←"
	// Gamepad right button up (i.e. PS3: Triangle, Xbox: Y)
	case .RIGHT_FACE_UP:
		return "Y"
	// Gamepad right button right (i.e. PS3: Circle, Xbox: B)
	case .RIGHT_FACE_RIGHT:
		return "B"
	// Gamepad right button down (i.e. PS3: Cross, Xbox: A)
	case .RIGHT_FACE_DOWN:
		return "A"
	// Gamepad right button left (i.e. PS3: Square, Xbox: X)
	case .RIGHT_FACE_LEFT:
		return "X"
	// Gamepad top/back trigger left (first), it could be a trailing button
	case .LEFT_TRIGGER_1:
		return "LB"
	// Gamepad top/back trigger left (second), it could be a trailing button
	case .LEFT_TRIGGER_2:
		return "LT"
	// Gamepad top/back trigger right (first), it could be a trailing button
	case .RIGHT_TRIGGER_1:
		return "RB"
	// Gamepad top/back trigger right (second), it could be a trailing button
	case .RIGHT_TRIGGER_2:
		return "RT"
	// Gamepad center buttons, left one (i.e. PS3: Select)
	case .MIDDLE_LEFT:
		return "SELECT"
	// Gamepad center buttons, middle one (i.e. PS3: PS, Xbox: XBOX)
	case .MIDDLE:
		return "(LOGO)"
	// Gamepad center buttons, right one (i.e. PS3: Start)
	case .MIDDLE_RIGHT:
		return "START"
	// Gamepad joystick pressed button left
	case .LEFT_THUMB:
		return "L3"
	// Gamepad joystick pressed button right
	case .RIGHT_THUMB:
		return "R3"
	}
	return "UNKNOWN"
}

get_key_name :: proc(gamepad_id: i32, controls: Controls, upgrade_index: int) -> string {
	key := controls.upgrade[upgrade_index]
	key_text := ""
	#partial switch key {
	case .APOSTROPHE:
		key_text = "'"
	case .COMMA:
		key_text = ","
	case .MINUS:
		key_text = "-"
	case .PERIOD:
		key_text = "."
	case .SLASH:
		key_text = "/"
	case .ZERO:
		key_text = "0"
	case .ONE:
		key_text = "1"
	case .TWO:
		key_text = "2"
	case .THREE:
		key_text = "3"
	case .FOUR:
		key_text = "4"
	case .FIVE:
		key_text = "5"
	case .SIX:
		key_text = "6"
	case .SEVEN:
		key_text = "7"
	case .EIGHT:
		key_text = "8"
	case .NINE:
		key_text = "9"
	case .SEMICOLON:
		key_text = ";"
	case .EQUAL:
		key_text = "="
	case .A:
		key_text = "A"
	case .B:
		key_text = "B"
	case .C:
		key_text = "C"
	case .D:
		key_text = "D"
	case .E:
		key_text = "E"
	case .F:
		key_text = "F"
	case .G:
		key_text = "G"
	case .H:
		key_text = "H"
	case .I:
		key_text = "I"
	case .J:
		key_text = "J"
	case .K:
		key_text = "K"
	case .L:
		key_text = "L"
	case .M:
		key_text = "M"
	case .N:
		key_text = "N"
	case .O:
		key_text = "O"
	case .P:
		key_text = "P"
	case .Q:
		key_text = "Q"
	case .R:
		key_text = "R"
	case .S:
		key_text = "S"
	case .T:
		key_text = "T"
	case .U:
		key_text = "U"
	case .V:
		key_text = "V"
	case .W:
		key_text = "W"
	case .X:
		key_text = "X"
	case .Y:
		key_text = "Y"
	case .Z:
		key_text = "Z"
	case .LEFT_BRACKET:
		key_text = "["
	case .BACKSLASH:
		key_text = "\\"
	case .RIGHT_BRACKET:
		key_text = "]"
	case .GRAVE:
		key_text = "`"
	case .SPACE:
		key_text = "Space"
	case .ESCAPE:
		key_text = "Esc"
	case .ENTER:
		key_text = "Enter"
	case .TAB:
		key_text = "Tab"
	case .BACKSPACE:
		key_text = "Backspace"
	case .INSERT:
		key_text = "Ins"
	case .DELETE:
		key_text = "Del"
	case .RIGHT:
		key_text = "Right"
	case .LEFT:
		key_text = "Left"
	case .DOWN:
		key_text = "Down"
	case .UP:
		key_text = "Up"
	case .PAGE_UP:
		key_text = "Page Up"
	case .PAGE_DOWN:
		key_text = "Page Down"
	case .HOME:
		key_text = "Home"
	case .END:
		key_text = "End"
	case .F1:
		key_text = "F1"
	case .F2:
		key_text = "F2"
	case .F3:
		key_text = "F3"
	case .F4:
		key_text = "F4"
	case .F5:
		key_text = "F5"
	case .F6:
		key_text = "F6"
	case .F7:
		key_text = "F7"
	case .F8:
		key_text = "F8"
	case .F9:
		key_text = "F9"
	case .F10:
		key_text = "F10"
	case .F11:
		key_text = "F11"
	case .F12:
		key_text = "F12"
	case .KP_0:
		key_text = "KP 0"
	case .KP_1:
		key_text = "KP 1"
	case .KP_2:
		key_text = "KP 2"
	case .KP_3:
		key_text = "KP 3"
	case .KP_4:
		key_text = "KP 4"
	case .KP_5:
		key_text = "KP 5"
	case .KP_6:
		key_text = "KP 6"
	case .KP_7:
		key_text = "KP 7"
	case .KP_8:
		key_text = "KP 8"
	case .KP_9:
		key_text = "KP 9"
	case .KP_DECIMAL:
		key_text = "KP ."
	case .KP_DIVIDE:
		key_text = "KP /"
	case .KP_MULTIPLY:
		key_text = "KP *"
	case .KP_SUBTRACT:
		key_text = "KP -"
	case .KP_ADD:
		key_text = "KP +"
	case .KP_ENTER:
		key_text = "KP Enter"
	case .KP_EQUAL:
		key_text = "KP ="
	case:
		key_text = "UNKNOWN"
	}

	if rl.IsGamepadAvailable(gamepad_id) {
		return fmt.tprintf("(%s) | %s", button_to_name(id_to_button(upgrade_index)), key_text)
	}
	return key_text
}

draw_hud :: proc(game: ^StateGame, player: ^Player) {
	rl.DrawRectangle(0, 0, g_obj.screen_width / 2, HELP_TEXT_HEIGHT, rl.BLACK)
	text := fmt.ctprintf(
		"PLAYER%d: %s/%s/%s/%s to move",
		player.id + 1,
		g_obj.settings.key_bindings[player.id].up,
		g_obj.settings.key_bindings[player.id].left,
		g_obj.settings.key_bindings[player.id].down,
		g_obj.settings.key_bindings[player.id].right,
	)
	draw_text_with_shadow(text, 10, 10, 10, rl.MAROON)
	bar_x := PROGRESS_BAR_PADDING
	bar_y := HELP_TEXT_HEIGHT + PROGRESS_BAR_PADDING
	full_bar_width := (g_obj.screen_width / 2) - (2 * PROGRESS_BAR_PADDING)
	rl.DrawRectangle(
		bar_x - 5,
		bar_y - 5,
		full_bar_width + 10,
		PROGRESS_BAR_HEIGHT + 10,
		rl.Fade(rl.RAYWHITE, 0.6),
	)

	text = fmt.ctprintf("%d/%d", fa.len(player.enemies), g_conf.balancing.max_enemies)
	draw_text_with_shadow(
		text,
		bar_x + full_bar_width / 2 - rl.MeasureText(text, 20) / 2,
		bar_y,
		20,
		rl.ORANGE,
	)

	text = fmt.ctprintf("Level: % 3d", player.exp.level)
	draw_text_with_shadow(text, bar_x + PROGRESS_BAR_PADDING, bar_y, 20, rl.ORANGE)

	if .GodMode in g_obj.debug_flags {
		text = TEXT_GOD_MODE
	} else {
		text = fmt.ctprintf("HP: %d/%d", player.hp, player.stats.max_hp.value)
	}
	draw_text_with_shadow(
		text,
		bar_x + full_bar_width - (rl.MeasureText(text, 20) + PROGRESS_BAR_PADDING),
		bar_y,
		20,
		rl.ORANGE,
	)

	// Calculate XP bar
	xp_bar_y := bar_y + PROGRESS_BAR_PADDING + PROGRESS_BAR_HEIGHT
	rl.DrawRectangle(
		bar_x - 5,
		xp_bar_y - 5,
		full_bar_width + 10,
		PROGRESS_BAR_HEIGHT + 10,
		rl.Fade(rl.RAYWHITE, 0.6),
	)

	xp_ratio := clamp(f32(player.exp.current) / f32(player.exp.needed), 0, 1)
	xp_width := i32(f32(full_bar_width) * xp_ratio)
	rl.DrawRectangle(
		bar_x,
		xp_bar_y,
		xp_width,
		PROGRESS_BAR_HEIGHT,
		rl.ColorLerp(rl.WHITE, rl.BLUE, xp_ratio),
	)
	text = fmt.ctprintf("%d/%d", player.exp.current, player.exp.needed)
	draw_text_with_shadow(
		text,
		bar_x + full_bar_width / 2 - rl.MeasureText(text, 20) / 2,
		xp_bar_y,
		20,
		rl.ORANGE,
	)

	last_size: i32 = 0
	for upgrade, i in slice(&player.available_upgrades) {
		key_name := get_key_name(player.gamepad_id, g_obj.settings.key_bindings[player.id], i)
		switch upgrade.type {
		case .NewWeapon:
			text = fmt.ctprintf("[%s] Weapon: %s", key_name, get_weapon_name(upgrade.weapon))
		case .MaxHP:
			text = fmt.ctprintf(
				"[%s] Max HP: %s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
			)
		case .MovementSpeed:
			text = fmt.ctprintf(
				"[%s] Movement Speed: %s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
			)
		case .LowerCooldown:
			text = fmt.ctprintf(
				"[%s] Cooldown - %s%s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
				get_weapon_name_for_upgrade(upgrade.weapon),
			)
		case .MoreDamage:
			text = fmt.ctprintf(
				"[%s] Damage + %s%s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
				get_weapon_name_for_upgrade(upgrade.weapon),
			)
		case .BiggerSize:
			text = fmt.ctprintf(
				"[%s] Area + %s%s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
				get_weapon_name_for_upgrade(upgrade.weapon),
			)
		case .PickupRange:
			text = fmt.ctprintf(
				"[%s] Pickup Range + %s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
			)
		case .XpGain:
			text = fmt.ctprintf(
				"[%s] Xp Gain + %s",
				key_name,
				increase_to_string(upgrade.amount, upgrade.amount_type),
			)
		}

		text_size := rl.MeasureText(text, 20)
		bar_width := text_size + PROGRESS_BAR_PADDING

		rl.DrawRectangle(
			bar_x + last_size + (PROGRESS_BAR_PADDING * i32(i)),
			xp_bar_y + (PROGRESS_BAR_HEIGHT + PROGRESS_BAR_PADDING),
			bar_width,
			PROGRESS_BAR_HEIGHT + 10,
			rl.Fade(rl.RAYWHITE, 0.6),
		)
		draw_text_with_shadow(
			text,
			bar_x + last_size + (PROGRESS_BAR_PADDING * i32(i)) + bar_width / 2 - text_size / 2,
			xp_bar_y +
			(PROGRESS_BAR_HEIGHT + PROGRESS_BAR_PADDING) +
			(PROGRESS_BAR_HEIGHT / 2) -
			5,
			20,
			rl.ORANGE,
		)

		last_size += text_size + 10
	}
}

draw_alpha_warning :: proc() {
	warn_y := g_obj.screen_height - (BALANCE_BAR_HEIGHT + BALANCE_BAR_PADDING) * 2
	alpha_size := rl.MeasureText(TEXT_ALPHA, 20)
	draw_text_with_shadow(
		TEXT_ALPHA,
		g_obj.screen_width / 2 - (alpha_size + 10),
		warn_y,
		TEXT_ALPHA_FONT_SIZE,
		rl.WHITE,
		rl.ColorLerp(rl.RED, rl.BLACK, 0.5),
	)
	draw_text_with_shadow(
		TEXT_BUILD,
		g_obj.screen_width / 2 + 10,
		warn_y,
		TEXT_ALPHA_FONT_SIZE,
		rl.BLACK,
		rl.ColorLerp(rl.RED, rl.WHITE, 0.5),
	)
}

draw_balance_bar :: proc(game: ^StateGame) {
	player1_enemies := fa.len(g_obj.players[0].enemies)
	player2_enemies := fa.len(g_obj.players[1].enemies)
	total_enemies := player1_enemies + player2_enemies

	bar_width := g_obj.screen_width - (2 * BALANCE_BAR_PADDING)
	bar_x := BALANCE_BAR_PADDING
	bar_y := g_obj.screen_height - BALANCE_BAR_HEIGHT - BALANCE_BAR_PADDING

	// Calculate proportions
	p1_ratio := f32(player1_enemies) / f32(total_enemies)

	p2_width := i32(f32(bar_width) * p1_ratio)
	p1_width := bar_width - p2_width // Ensure it fills the entire bar

	// Background Bar
	rl.DrawRectangle(bar_x - 5, bar_y - 5, bar_width + 10, BALANCE_BAR_HEIGHT + 10, rl.GRAY)

	// Player 1 Portion
	rl.DrawRectangle(bar_x, bar_y, p1_width, BALANCE_BAR_HEIGHT, rl.WHITE)

	// Player 2 Portion
	rl.DrawRectangle(bar_x + p1_width, bar_y, p2_width, BALANCE_BAR_HEIGHT, rl.BLACK)

	text := cstring("<- BALANCE ->")
	size := rl.MeasureTextEx(rl.GetFontDefault(), text, 20, 5)
	draw_text_with_shadow_ex(
		rl.GetFontDefault(),
		text,
		Vec2{(f32(g_obj.screen_width) / 2) - (size.x / 2), f32(bar_y - 5) + (size.y / 4)},
		20,
		5,
		rl.GRAY,
	)
}

draw :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.BLACK)

	#partial switch _ in state() {
	case StateGame:
		game := state(StateGame)
		draw_game(game)
	case StatePause:
		game := previous_state(StateGame)
		draw_game(game)

		pause := state(StatePause)
		draw_pause_menu(pause)

	case StateGameOver:
		rl.ClearBackground(rl.DARKGRAY)

		game_over := state(StateGameOver)

		rl.DrawText(TEXT_ALPHA_BUILD, 10, 10, TEXT_ALPHA_BUILD_FONT_SIZE, rl.WHITE)

		font := rl.GetFontDefault()
		text: cstring
		switch game_over.winner {
		case Winner.Player1:
			text = cstring("White wins!")
		case Winner.Player2:
			text = cstring("Black wins!")
		case Winner.Draw:
			text = cstring("It's a draw!")
		}
		text_size := rl.MeasureTextEx(font, text, 40, MENU_FONT_SPACING)
		text_x := (f32(g_obj.screen_width) - text_size.x) / 2
		text_y := (f32(g_obj.screen_height) - text_size.y) / 2
		draw_text_with_shadow_ex(
			font,
			text,
			Vec2{text_x, text_y},
			40,
			MENU_FONT_SPACING,
			rl.RAYWHITE,
		)
	case StateMenu:
		menu := state(StateMenu)
		rl.ClearBackground(rl.DARKGRAY)

		rl.DrawText(TEXT_ALPHA_BUILD, 10, 10, TEXT_ALPHA_BUILD_FONT_SIZE, rl.WHITE)

		draw_menu(
			MAIN_MENU_ITEMS,
			MainMenuAction,
			&menu.menu,
			MENU_FONT_SIZE,
			MENU_FONT_SPACING,
			0,
			0,
		)
	}

	if rl.IsCursorHidden() && rl.IsCursorOnScreen() && is_in_menu() {
		mp := rl.GetMousePosition()
		rl.DrawTriangle(mp, mp + {5, 10}, mp + {10, 5}, rl.WHITE)
		rl.DrawTriangleLines(mp, mp + {5, 10}, mp + {10, 5}, rl.BLACK)
	}
}
