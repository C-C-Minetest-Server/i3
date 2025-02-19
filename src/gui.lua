local damage_enabled = core.settings:get_bool"enable_damage"

local model_aliases = i3.files.model_alias()
local PNG, styles, fs_elements, colors = i3.files.styles()

local sprintf = string.format
local VoxelArea, VoxelManip = VoxelArea, VoxelManip

IMPORT("clr", "ESC", "check_privs")
IMPORT("find", "match", "sub", "upper")
IMPORT("vec_new", "vec_sub", "vec_round")
IMPORT("min", "max", "floor", "ceil", "round")
IMPORT("reg_items", "reg_tools", "reg_entities")
IMPORT("get_bag_description", "get_detached_inv")
IMPORT("S", "ES", "translate", "ItemStack", "toupper")
IMPORT("groups_to_items", "compression_active", "compressible")
IMPORT("true_str", "is_fav", "is_num", "get_group", "str_to_pos")
IMPORT("maxn", "sort", "concat", "copy", "insert", "remove", "unpack")
IMPORT("get_sorting_idx", "is_group", "extract_groups", "item_has_groups")

local function fmt(elem, ...)
	if not fs_elements[elem] then
		return sprintf(elem, ...)
	end

	return sprintf(fs_elements[elem], ...)
end

local function repairable(tool)
	local def = reg_tools[tool]
	return i3.toolrepair and def and def.groups and def.groups.disable_repair ~= 1
end

local function weird_desc(str)
	return not true_str(str) or find(str, "\n") or not find(str, "%u")
end

local function snip(str, limit)
	return #str > limit and fmt("%s...", sub(str, 1, limit - 3)) or str
end

local function get_desc(item)
	if sub(item, 1, 1) == "_" then
		item = sub(item, 2)
	end

	local def = reg_items[item]

	if not def then
		return S("Unknown Item (@1)", item)
	end

	local desc = def.description

	if true_str(desc) then
		desc = desc:trim():match("[^\n]*"):gsub("_", " ")

		if not find(desc, "%u") then
			desc = toupper(desc)
		end

		return desc

	elseif true_str(item) then
		return toupper(match(item, ":(.*)"))
	end
end

local function get_stack_max(inv, data, is_recipe, rcp)
	local list = inv:get_list"main"
	local size = inv:get_size"main"
	local counts_inv, counts_rcp, counts = {}, {}, {}
	local rcp_usg = is_recipe and "recipe" or "usage"

	for _, it in pairs(rcp.items) do
		counts_rcp[it] = (counts_rcp[it] or 0) + 1
	end

	data.export_counts[rcp_usg] = {}
	data.export_counts[rcp_usg].rcp = counts_rcp

	for i = 1, size do
		local stack = list[i]

		if not stack:is_empty() then
			local item = stack:get_name()
			local count = stack:get_count()

			for name in pairs(counts_rcp) do
				if is_group(name) then
					local def = reg_items[item]

					if def then
						local groups = extract_groups(name)

						if item_has_groups(def.groups, groups) then
							counts_inv[name] = (counts_inv[name] or 0) + count
						end
					end
				end
			end

			counts_inv[item] = (counts_inv[item] or 0) + count
		end
	end

	data.export_counts[rcp_usg].inv = counts_inv

	for name in pairs(counts_rcp) do
		counts[name] = floor((counts_inv[name] or 0) / (counts_rcp[name] or 0))
	end

	local max_stacks = math.huge

	for _, count in pairs(counts) do
		if count < max_stacks then
			max_stacks = count
		end
	end

	return max_stacks
end

local function get_inv_slots(fs)
	local inv_x, inv_y, size, spacing = 0.22, 6.9, 1, 0.1

	fs"style_type[box;colors=#77777710,#77777710,#777,#777]"

	for i = 0, i3.HOTBAR_LEN - 1 do
		fs("box", i * size + inv_x + (i * spacing), inv_y, size, size, "")
	end

	fs(fmt("style_type[list;size=%f;spacing=%f]", size, spacing),
	   fmt("list[current_player;main;%f,%f;%u,1;]", inv_x, inv_y, i3.HOTBAR_LEN))

	fs(fmt("style_type[list;size=%f;spacing=%f]", size, spacing),
	   fmt("list[current_player;main;%f,%f;%u,%u;%u]", inv_x, inv_y + 1.15,
		i3.HOTBAR_LEN, i3.INV_SIZE / i3.HOTBAR_LEN, i3.HOTBAR_LEN),
	   "style_type[list;size=1;spacing=0.15]")

	fs"listring[current_player;craft]listring[current_player;main]"
end

local function add_subtitle(fs, name, y, ctn_len, font_size, sep, label)
	fs(fmt("style[%s;font=bold;font_size=%u]", name, font_size))
	fs("button", 0, y, ctn_len, 0.5, name, ESC(label))

	if sep then
		fs("image", 0, y + 0.55, ctn_len, 0.035, PNG.bar)
	end
end

local function get_award_list(data, fs, ctn_len, yextra, award_list, awards_unlocked, award_list_nb)
	local percent = fmt("%.1f%%", (awards_unlocked * 100) / award_list_nb):gsub("%.0", "")

	add_subtitle(fs, "awards", yextra, ctn_len, 18, false,
		ES("Achievements: @1 of @2 (@3)", awards_unlocked, award_list_nb, percent))

	for i = 1, award_list_nb do
		local award = award_list[i]
		local y = yextra - 0.6 + i + (i * 0.3)

		local def, progress = award.def, award.progress
		local title, desc = def.title, def.description

		title = translate(data.lang_code, title)
		desc = translate(data.lang_code, desc):gsub("%.$", "")

		local title_lim, _title = 27
		local desc_lim, _desc = 39
		local icon_size = 1.1

		if #title > title_lim then
			_title = snip(title, title_lim)
		end

		if #desc > desc_lim then
			_desc = snip(desc, desc_lim)
		end

		if not award.unlocked and def.secret then
			title = ES"Secret award"
			desc = ES"Unlock this award to find out what it is"
		end

		local icon = def.icon or "awards_unknown.png"

		if not award.unlocked then
			icon = fmt("%s^\\[colorize:#000:200", icon)
		end

		insert(fs, fmt("image", 0, y, icon_size, icon_size, icon))
		insert(fs, "style_type[box;colors=#bababa30,#bababa30,#bababa05,#bababa05]")
		insert(fs, fmt("box", 0, y, ctn_len, icon_size, ""))

		if progress then
			local box_len = ctn_len - icon_size - 0.15
			local current, target = progress.current, progress.target
			local curr_bar = (current * box_len) / target

			insert(fs, fmt("box", icon_size + 0.15, y + 0.8, box_len, 0.3, "#101010"))
			insert(fs, "style_type[box;colors=#9dc34c80,#9dc34c,#9dc34c,#9dc34c80]")
			insert(fs, fmt("box", icon_size + 0.15, y + 0.8, curr_bar, 0.3, ""))
			insert(fs, "style_type[label;font_size=14]")
			insert(fs, fmt("label", icon_size + 0.55, y + 0.97, fmt("%u / %u", current, target)))

			y -= 0.14
		end

		local end_title = ESC(_title or title)
		local end_desc = ESC(_desc or desc)

		insert(fs, "style_type[label;font=bold;font_size=17]")
		insert(fs, fmt("label", icon_size + 0.2, y + 0.4, end_title))
		insert(fs, "style_type[label;font=normal;font_size=15]")
		insert(fs, fmt("label", icon_size + 0.2, y + 0.75, clr("#bbb", end_desc)))
		insert(fs, "style_type[label;font_size=16]")
		insert(fs, fmt("tooltip", 0, y, icon_size, icon_size, ESC(desc)))
	end
end

local function get_isometric_view(fs, pos, X, Y)
	pos = vec_round(pos)
	local width = 8

	local pos1 = vec_new(pos.x - width, pos.y - 1, pos.z - width)
	local pos2 = vec_new(pos.x + width, pos.y + 3, pos.z + width)
	core.emerge_area(pos1, pos2)

	local vm = VoxelManip(pos1, pos2)
	local emin, emax = vm:read_from_map(pos1, pos2)
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data()

	for idx in area:iterp(pos1, pos2) do
		local cube = i3.cubes[data[idx]]
		local plant = i3.plants[data[idx]]
		local img = cube or plant

		if img then
			local p = area:position(idx)
			      p = vec_sub(p, pos)

			local size = 0.25
			local x = 2 + (size / 2 * (p.z - p.x))
			local y = 1.15 + (size / 4 * (p.x + p.z - 2 * p.y))

			if plant then
				size -= 0.05
			end

			insert(fs, fmt("image[%f,%f;%.1f,%.1f;%s]", x + X, y + Y, size, size, img))
		end
	end
end

local function get_waypoint_fs(fs, data, player, yextra, ctn_len)
	fs(fmt("box[0,%f;4.9,0.6;#bababa25]", yextra + 1.1))
	fs("label", 0, yextra + 0.85, ES"Waypoint name:")
	fs(fmt("field[0.1,%f;4.8,0.6;waypoint_name;;]", yextra + 1.1))
	fs("image_button", 5.1, yextra + 1.15, 0.5, 0.5, "", "waypoint_add", "")
	fs(fmt("tooltip[waypoint_add;%s]", ES"Add waypoint"))

	if #data.waypoints == 0 then return end

	for i, v in ipairs(data.waypoints) do
		local y = yextra + 1.35 + (i - (i * 0.3))
		local icon_size, yi = 0.35, y + 0.12

		fs"style_type[box;colors=#bababa30,#bababa30,#bababa05,#bababa05]"
		fs("box", 0, y, ctn_len, 0.6, "")

		local waypoint_name, lim = v.name, 18

		if #v.name > lim then
			waypoint_name = snip(waypoint_name, lim)
		end

		fs"style_type[label;font_size=17]"

		local hex = fmt("%02x", v.color)

		while #hex < 6 do
			hex = "0" .. hex
		end

		local teleport_priv = check_privs(player, {teleport = true})
		local waypoint_preview = data.waypoint_see and data.waypoint_see == i

		fs("label", 0.15, y + 0.33, clr(fmt("#%s", hex), waypoint_name))

		local tooltip = fmt("Name: %s\nPosition:%s", clr("#dbeeff", v.name),
				v.pos:sub(2,-2):gsub("(%-*%d*%.?%d+)", clr("#dbeeff", " %1")))

		if teleport_priv then
			tooltip = fmt("%s\n%s", tooltip, clr("#ff0", ES"[Click to teleport]"))
		end

		fs("tooltip", 0, y, ctn_len - 2.1, 0.65, tooltip)

		local del = fmt("waypoint_%u_delete", i)
		fs(fmt("style[%s;fgimg=%s;fgimg_hovered=%s;content_offset=0]", del, PNG.trash, PNG.trash_hover))
		fs("image_button", ctn_len - 0.5, yi, icon_size, icon_size, "", del, "")
		fs(fmt("tooltip[%s;%s]", del, ES"Remove waypoint"))

		local rfs = fmt("waypoint_%u_refresh", i)
		fs(fmt("style[%s;fgimg=%s;fgimg_hovered=%s;content_offset=0]", rfs, PNG.refresh, PNG.refresh_hover))
		fs("image_button", ctn_len - 1, yi, icon_size, icon_size, "", rfs, "")
		fs(fmt("tooltip[%s;%s]", rfs, ES"Change color"))

		local see = fmt("waypoint_%u_see", i)
		fs(fmt("style[%s;fgimg=%s;fgimg_hovered=%s;content_offset=0]",
			see, waypoint_preview and PNG.search_hover or PNG.search, PNG.search, PNG.search_hover))
		fs("image_button", ctn_len - 1.5, yi, icon_size, icon_size, "", see, "")
		fs(fmt("tooltip[%s;%s]", see, ES"Preview the waypoint area"))

		local vsb = fmt("waypoint_%u_hide", i)
		fs(fmt("style[%s;fgimg=%s;content_offset=0]", vsb, v.hide and PNG.nonvisible or PNG.visible))
		fs("image_button", ctn_len - 2, yi, icon_size, icon_size, "", vsb, "")
		fs(fmt("tooltip[%s;%s]", vsb, v.hide and ES"Show waypoint" or ES"Hide waypoint"))

		if teleport_priv then
			local tp = fmt("waypoint_%u_teleport", i)
			fs("button", 0, y, ctn_len - 2.1, 0.6, tp, "")
		end

		if waypoint_preview then
			fs("image", 0.25, y - 3.5, 5, 4, PNG.bg_content)
			fs("button", 0.25, y - 3.35, 5, 0.55, "area_preview", v.name)
			fs("image_button", 4.65, y - 3.25, 0.25, 0.25,
				PNG.cancel_hover .. "^\\[brighten", "close_preview", "")

			local pos = str_to_pos(data.waypoints[i].pos)
			get_isometric_view(fs, pos, 0.6, y - 2.5)
			fs("image", 2.7, y - 1.5, 0.3, 0.3, PNG.flag)
		end
	end

	fs"style_type[label;font_size=16]"
end

local function get_bag_fs(fs, data, name, esc_name, bag_size, yextra)
	fs(fmt("list[detached:i3_bag_%s;main;0,%f;1,1;]", esc_name, yextra + 0.7))
	local bag = get_detached_inv("bag", name)
	if bag:is_empty"main" then return end

	local v = {{1.9, 2, 0.12}, {3.05, 5, 0.06}, {4.2, 10}, {4.75, 10}}
	local h, m, yy = unpack(v[bag_size])

	local bagstack = bag:get_stack("main", 1)
	local desc = ESC(get_bag_description(data, bagstack))

	fs("image", 0.5, yextra + 1.85, 0.6, 0.6, PNG.arrow_content)
	fs(fmt("style[bg_content;bgimg=%s;fgimg=i3_blank.png;bgimg_middle=10,%u;sound=]", PNG.bg_content, m))
	fs("image_button", 1.1, yextra + 0.5 + (yy or 0), 4.75, h, "", "bg_content", "")

	if not data.bag_rename then
		fs("hypertext", 1.3, yextra + 0.8, 4.3, 0.6, "content",
			fmt("<global size=16><center><b>%s</b></center>", desc))
		fs("image_button", 5.22, yextra + 0.835, 0.25, 0.25, "", "bag_rename", "")
		fs(fmt("tooltip[%s;%s]", "bag_rename", ES"Rename the bag"))
	else
		fs("box", 1.7, yextra + 0.82, 2.6, 0.4, "#707070")
		fs(fmt("field[1.8,%f;2.5,0.4;bag_newname;;%s]", yextra + 0.82, desc),
		   "field_close_on_enter[bag_newname;false]")
		fs("hypertext", 4.4, yextra + 0.88, 0.8, 0.6, "confirm_rename",
			fmt("<global size=16><tag name=action color=#fff hovercolor=%s>" ..
				"<center><b><action name=ok>OK</action></b></center>", colors.yellow))
	end

	local x, size, spacing = 1.45, 0.9, 0.12

	if bag_size == 4 then
		x, size, spacing = 1.7, 0.8, 0.1
	end

	fs(fmt("style_type[list;size=%f;spacing=%f]", size, spacing))
	fs(fmt("list[detached:i3_bag_content_%s;main;%f,%f;4,%u;]", esc_name, x, yextra + 1.3, bag_size))
	fs"style_type[list;size=1;spacing=0.15]"
end

local function get_container(fs, data, player, yoffset, ctn_len, award_list, awards_unlocked, award_list_nb, bag_size)
	local name = data.player_name
	local esc_name = ESC(name)

	add_subtitle(fs, "player_name", 0, ctn_len, 22, true, esc_name)

	if damage_enabled then
		local hp = data.hp or player:get_hp() or 20
		local half = ceil((hp / 2) % 1)
		local hearts = (hp / 2) + half
		local heart_size = 0.35
		local heart_x, heart_h = 0.65, yoffset + 0.75

		for i = 1, 10 do
			fs("image", heart_x + ((i - 1) * (heart_size + 0.1)), heart_h,
				heart_size, heart_size, PNG.heart_grey)
		end

		for i = 1, hearts do
			fs("image", heart_x + ((i - 1) * (heart_size + 0.1)), heart_h,
				heart_size, heart_size,
				(half == 1 and i == floor(hearts)) and PNG.heart_half or PNG.heart)
		end
	else
		yoffset -= 0.5
	end

	fs(fmt("list[current_player;craft;%f,%f;3,3;]", 0, yoffset + 1.45))
	fs("image", 3.47, yoffset + 2.69, 0.85, 0.85, PNG.arrow)
	fs(fmt("list[current_player;craftpreview;%f,%f;1,1;]", 4.45, yoffset + 2.6),
	   fmt("list[detached:i3_trash;main;%f,%f;1,1;]", 4.45, yoffset + 3.75))
	fs("image", 4.45, yoffset + 3.75, 1, 1, PNG.trash)

	local yextra = damage_enabled and 5.5 or 5

	for i, title in ipairs(i3.SUBCAT) do
		local btn_name = fmt("btn_%s", title)
		fs(fmt("style[btn_%s;fgimg=%s;fgimg_hovered=%s;content_offset=0]", title,
			data.subcat == i and PNG[fmt("%s_hover", title)] or PNG[title],
			PNG[fmt("%s_hover", title)]))
		fs("image_button", 0.25 + ((i - 1) * 1.18), yextra - 0.2, 0.5, 0.5, "", btn_name, "")
		fs(fmt("tooltip[%s;%s]", btn_name, title:gsub("^%l", upper)))
	end

	fs("box", 0, yextra + 0.45, ctn_len, 0.045, "#bababa50")
	fs("box", (data.subcat - 1) * 1.18, yextra + 0.45, 1, 0.045, "#f9826c")

	local function not_installed(modname)
		fs("hypertext", 0, yextra + 0.9, ctn_len, 0.6, "not_installed",
			fmt("<global size=16><center><style color=%s font=mono>%s</style> not installed</center>",
				colors.blue, modname))
	end

	if data.subcat == 1 then
		get_bag_fs(fs, data, name, esc_name, bag_size, yextra)

	elseif data.subcat == 2 then
		if not i3.modules.armor then
			return not_installed "3d_armor"
		end

		local armor_def = armor.def[name]
		fs(fmt("list[detached:%s_armor;armor;0,%f;3,2;]", esc_name, yextra + 0.7))
		fs("label", 3.65, yextra + 1.55, fmt("%s: %s", ES"Level", armor_def.level))
		fs("label", 3.65, yextra + 2.05, fmt("%s: %s", ES"Heal", armor_def.heal))

	elseif data.subcat == 3 then
		if not i3.modules.skins then
			return not_installed "skinsdb"
		end

		local _skins = skins.get_skinlist_for_player(name)
		local skin_name = skins.get_player_skin(player).name
		local sks, id = {}, 1

		for i, skin in ipairs(_skins) do
			if skin.name == skin_name then
				id = i
			end

			insert(sks, skin.name)
		end

		sks = concat(sks, ","):gsub(";", "")
		fs("label", 0, yextra + 0.85, fmt("%s:", ES"Select a skin"))
		fs(fmt("dropdown[0,%f;4,0.6;skins;%s;%u;true]", yextra + 1.1, sks, id))

	elseif data.subcat == 4 then
		if not i3.modules.awards then
			return not_installed "awards"
		end

		yextra = yextra + 0.7
		get_award_list(data, fs, ctn_len, yextra, award_list, awards_unlocked, award_list_nb)

	elseif data.subcat == 5 then
		get_waypoint_fs(fs, data, player, yextra, ctn_len)
	end
end

local function show_popup(fs, data)
	if data.confirm_trash then
		fs"style_type[box;colors=#999,#999,#808080,#808080]"

		for _ = 1, 3 do
			fs("box", 2.97, 10.75, 4.3, 0.5, "")
		end

		fs("label", 3.12, 11, "Confirm trash?")
		fs("image_button", 5.17, 10.75, 1, 0.5, "", "confirm_trash_yes", "Yes")
		fs("image_button", 6.27, 10.75, 1, 0.5, "", "confirm_trash_no", "No")

	elseif data.show_settings then
		fs"style_type[box;colors=#999,#999,#808080,#808080]"

		for _ = 1, 3 do
			fs("box", 2.1, 9.25, 6, 2, "")
		end

		for _ = 1, 3 do
			fs("box", 2.1, 9.25, 6, 0.5, "#707070")
		end

		fs("image_button", 7.75, 9.35, 0.25, 0.25, PNG.cancel_hover .. "^\\[brighten", "close_settings", "")

		local show_home = data.show_setting == "home"
		local show_sorting = data.show_setting == "sorting"
		local show_misc = data.show_setting == "misc"

		fs(fmt("style[setting_home;textcolor=%s;font=bold;sound=i3_click]",
			show_home and colors.yellow or "#fff"),
		   fmt("style[setting_sorting;textcolor=%s;font=bold;sound=i3_click]",
			show_sorting and colors.yellow or "#fff"),
		   fmt("style[setting_misc;textcolor=%s;font=bold;sound=i3_click]",
			show_misc and colors.yellow or "#fff"))

		fs("button", 2.2, 9.25, 1.8, 0.55, "setting_home", "Home")
		fs("button", 4,   9.25, 1.8, 0.55, "setting_sorting", "Sorting")
		fs("button", 5.8, 9.25, 1.8, 0.55, "setting_misc", "Misc.")

		if show_home then
			local coords, c, str = {"X", "Y", "Z"}, 0, ES"No home set"

			if data.home then
				str = data.home:gsub(",", "  "):sub(2,-2):gsub("%.%d", ""):gsub(
					"(%-?%d+)", function(a)
						c++
						return fmt("<b>%s: <style color=%s font=mono>%s</style></b>",
							coords[c], colors.black, a)
					end)
			end

			fs("hypertext", 2.1, 9.9, 6, 0.6, "home_pos", fmt("<global size=16><center>%s</center>", str))
			fs("image_button", 4.2, 10.4, 1.8, 0.7, "", "set_home", "Set home")

		elseif show_sorting then
			fs("button", 2.1, 9.7, 6, 0.8, "select_sorting", ES"Select the inventory sorting method:")

			fs(fmt("style[prev_sort;fgimg=%s;fgimg_hovered=%s]", PNG.prev, PNG.prev_hover),
			   fmt("style[next_sort;fgimg=%s;fgimg_hovered=%s]", PNG.next, PNG.next_hover))

			fs("image_button", 2.2, 10.6, 0.35, 0.35, "",  "prev_sort", "")
			fs("image_button", 7.65, 10.6, 0.35, 0.35, "", "next_sort", "")

			fs"style[sort_method;font=bold;font_size=20]"
			fs("button", 2.55, 10.36, 5.1, 0.8, "sort_method", toupper(data.sort))

			local idx = get_sorting_idx(data.sort)
			local desc = i3.sorting_methods[idx].description

			if desc then
				fs(fmt("tooltip[%s;%s]", "sort_method", desc))
			end

		elseif show_misc then
			fs("checkbox", 2.4, 10.05, "cb_inv_compress", "Compression", tostring(data.inv_compress))
			fs("checkbox", 2.4, 10.5,  "cb_reverse_sorting", "Reverse mode", tostring(data.reverse_sorting))
			fs("checkbox", 2.4, 10.95, "cb_ignore_hotbar", "Ignore hotbar", tostring(data.ignore_hotbar))
			fs("checkbox", 5.4, 10.05, "cb_auto_sorting", "Automation", tostring(data.auto_sorting))

			for _ = 1, 3 do
				fs("box", 5.4, 10.68, 2.4, 0.45, "#707070")
			end

			fs("style[drop_items;font_size=15;font=mono;textcolor=#dbeeff]",
			   fmt("field[5.4,10.68;2.4,0.45;drop_items;Drop items:;%s]",
				ESC(concat(data.drop_items or {}, ","))),
			   "field_close_on_enter[drop_items;false]")

			fs(fmt("tooltip[cb_inv_compress;%s;#707070;#fff]",
				ES"Enable this option to compress your inventory"),
			   fmt("tooltip[cb_reverse_sorting;%s;#707070;#fff]",
				ES"Enable this option to sort your inventory in reverse order"),
			   fmt("tooltip[cb_ignore_hotbar;%s;#707070;#fff]",
				ES"Enable this option to sort your inventory except the hotbar slots"),
			   fmt("tooltip[cb_auto_sorting;%s;#707070;#fff]",
				ES"Enable this option to sort your inventory automatically"),
			   fmt("tooltip[drop_items;%s;#707070;#fff]",
				"Add a comma-separated list of items to drop on inventory sorting.\n" ..
				"Format: " .. ("mod:item,mod:item, ..."):gsub("(%a+:%a+)", clr("#bddeff", "%1"))))
		end
	end
end

local function get_inventory_fs(player, data, fs)
	fs"listcolors[#bababa50;#bababa99]"

	get_inv_slots(fs)

	local props = player:get_properties()
	local ctn_len, ctn_hgt, yoffset = 5.7, 6.3, 0

	if props.mesh ~= "" then
		local anim = player:get_local_animation()
		local armor_skin = i3.modules.armor or i3.modules.skins
		local t = {}

		for _, v in ipairs(props.textures) do
			insert(t, (ESC(v):gsub(",", "!")))
		end

		local textures = concat(t, ","):gsub("!", ",")

		--fs("style[player_model;bgcolor=black]")
		fs("model", 0.2, 0.2, armor_skin and 4 or 3.4, ctn_hgt,
			"player_model", props.mesh, textures, "0,-150", "false", "false",
			fmt("%u,%u%s", anim.x, anim.y, data.fs_version >= 5 and ";30" or ""))
	else
		local size = 2.5
		fs("image", 0.7, 0.2, size, size * props.visual_size.y, props.textures[1])
	end

	local awards_unlocked, award_list, award_list_nb = 0
	local max_val = damage_enabled and 12 or 7
	local bag_size = get_group(ItemStack(data.bag):get_name(), "bag")

	if data.subcat == 1 and bag_size > 0 then
		max_val += min(32, 6 + ((bag_size - 1) * 10))

	elseif i3.modules.armor and data.subcat == 2 then
		if data.scrbar_inv >= max_val then
			data.scrbar_inv += 10
		end

		max_val += 10

	elseif i3.modules.awards and data.subcat == 4 then
		award_list = awards.get_award_states(data.player_name)
		award_list_nb = #award_list

		for i = 1, award_list_nb do
			local award = award_list[i]

			if award.unlocked then
				awards_unlocked++
			end
		end

		max_val += (award_list_nb * 13)

	elseif data.subcat == 5 then
		local wp_nb = #data.waypoints

		if wp_nb > 0 then
			local mul = (wp_nb > 8 and 7) or (wp_nb > 4 and 6) or 5
			max_val += 11 + (wp_nb * mul)
		end
	end

	fs(fmt([[
		scrollbaroptions[arrows=hide;thumbsize=%d;max=%d]
		scrollbar[%f,0.2;0.2,%f;vertical;scrbar_inv;%u]
		scrollbaroptions[arrows=default;thumbsize=0;max=1000]
	]],
	(max_val * 4) / 12, max_val, 9.8, ctn_hgt, data.scrbar_inv))

	fs(fmt("scroll_container[3.9,0.2;%f,%f;scrbar_inv;vertical]", ctn_len, ctn_hgt))
	get_container(fs, data, player, yoffset, ctn_len, award_list, awards_unlocked, award_list_nb, bag_size)
	fs"scroll_container_end[]"

	local btn = {
		{"trash",    ES"Clear inventory"},
		{"sort",     ES"Sort inventory"},
		{"settings", ES"Settings"},
		{"home",     ES"Go home"},
	}

	for i, v in ipairs(btn) do
		local btn_name, tooltip = unpack(v)
		fs(fmt("style[%s;fgimg=%s;fgimg_hovered=%s;content_offset=0]",
			btn_name, PNG[btn_name], PNG[fmt("%s_hover", btn_name)]))
		fs("image_button", i + 3.43 - (i * 0.4), 11.43, 0.35, 0.35, "", btn_name, "")
		fs(fmt("tooltip[%s;%s]", btn_name, tooltip))
	end

	show_popup(fs, data)
end

local function get_tooltip(item, info, pos)
	local tooltip

	if info.groups then
		sort(info.groups)
		tooltip = i3.group_names[concat(info.groups, ",")]

		if not tooltip then
			local groupstr = {}

			for i = 1, #info.groups do
				insert(groupstr, clr("#ff0", info.groups[i]))
			end

			groupstr = concat(groupstr, ", ")
			tooltip = S("Any item belonging to the groups: @1", groupstr)
		end
	else
		tooltip = info.meta_desc or get_desc(item)
	end

	local function add(str)
		return fmt("%s\n%s", tooltip, str)
	end

	if info.cooktime then
		tooltip = add(S("Cooking time: @1", clr("#ff0", info.cooktime)))
	end

	if info.burntime then
		tooltip = add(S("Burning time: @1", clr("#ff0", info.burntime)))
	end

	if info.replace then
		for i = 1, #info.replace.items do
			local rpl = ItemStack(info.replace.items[i]):get_name()
			local desc = clr("#ff0", get_desc(rpl))

			if info.replace.type == "cooking" then
				tooltip = add(S("Replaced by @1 on smelting", desc))
			elseif info.replace.type == "fuel" then
				tooltip = add(S("Replaced by @1 on burning", desc))
			else
				tooltip = add(S("Replaced by @1 on crafting", desc))
			end
		end
	end

	if info.repair then
		tooltip = add(S("Repairable by step of @1", clr("#ff0", i3.toolrepair .. "%")))
	end

	if info.rarity then
		local chance = (1 / max(1, info.rarity)) * 100
		tooltip = add(S("@1 of chance to drop", clr("#ff0", chance .. "%")))
	end

	if info.tools then
		local several = #info.tools > 1
		local names = several and "\n" or ""

		if several then
			for i = 1, #info.tools do
				names = fmt("%s\t\t- %s\n", names, clr("#ff0", get_desc(info.tools[i])))
			end

			tooltip = add(S("Only drop if using one of these tools: @1", sub(names, 1, -2)))
		else
			tooltip = add(S("Only drop if using this tool: @1", clr("#ff0", get_desc(info.tools[1]))))
		end
	end

	if pos then
		return fmt("tooltip", pos.x, pos.y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE, ESC(tooltip))
	end

	return fmt("tooltip[%s;%s]", item, ESC(tooltip))
end

local function get_output_fs(fs, data, rcp, is_recipe, shapeless, right, btn_size, _btn_size)
	local custom_recipe = i3.craft_types[rcp.type]

	if custom_recipe or shapeless or rcp.type == "cooking" then
		local icon = custom_recipe and custom_recipe.icon or shapeless and "shapeless" or "furnace"

		if not custom_recipe then
			icon = fmt("i3_%s.png^\\[resize:16x16", icon)
		end

		local pos_x = right + btn_size + 0.42
		local pos_y = data.yoffset + 0.9

		if sub(icon, 1, 10) == "i3_furnace" then
			fs("animated_image", pos_x, pos_y, 0.5, 0.5, PNG.furnace_anim, 8, 180)
		else
			fs("image", pos_x, pos_y, 0.5, 0.5, icon)
		end

		local tooltip = custom_recipe and custom_recipe.description or
				shapeless and S"Shapeless" or S"Cooking"

		fs("tooltip", pos_x, pos_y, 0.5, 0.5, ESC(tooltip))
	end

	local arrow_X = right + 0.2 + (_btn_size or i3.ITEM_BTN_SIZE)
	local X = arrow_X + 1.2
	local Y = data.yoffset + 1.4

	fs("image", arrow_X, Y + 0.06, 1, 1, PNG.arrow)

	if rcp.type == "fuel" then
		fs("animated_image", X + 0.05, Y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE, PNG.fire_anim, 8, 180)
		return
	end

	local item  = ItemStack(rcp.output)
	local meta  = item:get_meta()
	local name  = item:get_name()
	local count = item:get_count()
	local wear  = item:get_wear()
	local bt_s  = i3.ITEM_BTN_SIZE * 1.2
	local _name = fmt("_%s", name)
	local pos

	if meta:get_string"color" ~= "" or meta:get_string"palette_index" ~= "" then
		local rcp_usg = is_recipe and "rcp" or "usg"

		fs(fmt("style_type[list;size=%f]", i3.ITEM_BTN_SIZE))
		fs"listcolors[#bababa50;#bababa99]"
		fs(fmt("list[detached:i3_output_%s_%s;main;%f,%f;1,1;]", rcp_usg, data.player_name, X + 0.11, Y))
		fs("button",  X + 0.11, Y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE, _name, "")

		local inv = get_detached_inv(fmt("output_%s", rcp_usg), data.player_name)
		inv:set_stack("main", 1, item)
		pos = {x = X + 0.11, y = Y}
	else
		fs("image", X, Y - 0.11, bt_s, bt_s, PNG.slot)
		fs("item_image_button",
			X + 0.11, Y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE,
			fmt("%s %u %u", name, count * (is_recipe and data.scrbar_rcp or data.scrbar_usg or 1), wear),
			_name, "")
	end

	local def = reg_items[name]
	local unknown = not def or nil
	local desc = def and def.description
	local weird = name ~= "" and desc and weird_desc(desc) or nil
	local burntime = i3.fuel_cache[name] and i3.fuel_cache[name].burntime

	local short_desc = meta:get_string"short_description"
	local long_desc  = meta:get_string"description"
	local meta_desc  = (short_desc ~= "" and short_desc) or (long_desc ~= "" and long_desc)

	local infos = {
		unknown   = unknown,
		weird     = weird,
		burntime  = burntime,
		repair    = repairable(name),
		rarity    = rcp.rarity,
		tools     = rcp.tools,
		meta_desc = meta_desc,
	}

	if next(infos) then
		fs(get_tooltip(_name, infos, pos))
	end
end

local function get_grid_fs(fs, data, rcp, is_recipe)
	local width = rcp.width or 1
	local right, btn_size, _btn_size = 0, i3.ITEM_BTN_SIZE
	local cooktime, shapeless

	if rcp.type == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 and not rcp.custom then
		shapeless = true
		local n = #rcp.items
		width = (n < 5 and n > 1) and 2 or min(3, max(1, n))
	end

	local rows = ceil(maxn(rcp.items) / width)
	local large_recipe = width > 3 or rows > 3

	if large_recipe then
		fs"style_type[item_image_button;border=true]"
	end

	for i = 1, width * rows do
		local item  = rcp.items[i] or ""
		      item  = ItemStack(item)
		local meta  = item:get_meta()
		local name  = item:get_name()
		local count = item:get_count()
		local X, Y

		if large_recipe then
			local a, b = 3, 3
			local add_x, add_y = 0, 0

			if width < 3 then
				a, b = width * 2, 1
				add_x = 2
			elseif rows < 3 then
				a, b = 1, rows * 2
				add_y = 1.4
			end

			btn_size = (a / width) * (b / rows) + 0.3
			_btn_size = btn_size

			local xi = (i - 1) % width
			local yi = floor((i - 1) / width)

			X = btn_size * xi + data.inv_width + 0.3 + (xi * 0.05) + add_x
			Y = btn_size * yi + data.yoffset + 0.2 + (yi * 0.05) + add_y
		else
			X = ceil((i - 1) % width - width)
			X += (X * 0.2) + data.inv_width + 3.9

			Y = ceil(i / width) - min(2, rows)
			Y += (Y * 0.15) + data.yoffset + 1.4
		end

		if X > right then
			right = X
		end

		local groups

		if is_group(name) then
			groups = extract_groups(name)
			name = groups_to_items(groups)
		end

		local label = groups and "\nG" or ""
		local replace

		for j = 1, #(rcp.replacements or {}) do
			local replacement = rcp.replacements[j]
			if replacement[1] == name then
				replace = replace or {type = rcp.type, items = {}}

				local added

				for _, v in ipairs(replace.items) do
					if replacement[2] == v then
						added = true
						break
					end
				end

				if not added then
					label = fmt("%s%s\nR", label ~= "" and "\n" or "", label)
					insert(replace.items, replacement[2])
				end
			end
		end

		if not large_recipe then
			fs("image", X, Y, btn_size, btn_size, PNG.slot)
		end

		local btn_name = groups and fmt("group!%s!%s", groups[1], name) or name

		fs("item_image_button", X, Y, btn_size, btn_size,
			fmt("%s %u", name, count * (is_recipe and data.scrbar_rcp or data.scrbar_usg or 1)),
			btn_name, label)

		local def = reg_items[name]
		local unknown = not def or nil
		      unknown = not groups and unknown or nil
		local desc = def and def.description
		local weird = name ~= "" and desc and weird_desc(desc) or nil
		local burntime = i3.fuel_cache[name] and i3.fuel_cache[name].burntime

		local short_desc = meta:get_string"short_description"
		local long_desc  = meta:get_string"description"
		local meta_desc  = (short_desc ~= "" and short_desc) or (long_desc ~= "" and long_desc) or nil

		local infos = {
			unknown   = unknown,
			weird     = weird,
			groups    = groups,
			burntime  = burntime,
			cooktime  = cooktime,
			replace   = replace,
			meta_desc = meta_desc,
		}

		if next(infos) then
			fs(get_tooltip(btn_name, infos))
		end
	end

	if large_recipe then
		fs("style_type[item_image_button;border=false]")
	end

	get_output_fs(fs, data, rcp, is_recipe, shapeless, right, btn_size, _btn_size)
end

local function get_rcp_lbl(fs, data, panel, rn, is_recipe)
	local rcp = is_recipe and panel.rcp[data.rnum] or panel.rcp[data.unum]

	if rcp.custom then
		fs("hypertext", data.inv_width + 4.8, data.yoffset + 0.12, 3, 0.6, "custom_rcp",
			fmt("<global size=16><right><i>%s</i></right>", ES"Custom recipe"))
	end

	local lbl = ES("Usage @1 of @2", data.unum, rn)

	if is_recipe then
		lbl = ES("Recipe @1 of @2", data.rnum, rn)
	end

	local one = rn == 1
	local y = data.yoffset + 3.3

	fs("hypertext", data.inv_width + (one and 4.7 or 3.95), y, 3, 0.6, "rcp_num",
		fmt("<global size=16><right>%s</right>", lbl))

	if not one then
		local btn_suffix = is_recipe and "recipe" or "usage"
		local prev_name = fmt("prev_%s", btn_suffix)
		local next_name = fmt("next_%s", btn_suffix)
		local size = 0.3

		fs("image_button", data.inv_width + 7.05, y, size, size, "", prev_name, "")
		fs("image_button", data.inv_width + 7.5,  y, size, size, "", next_name, "")
	end

	get_grid_fs(fs, data, rcp, is_recipe)
end

local function get_model_fs(fs, data, def, model_alias)
	if model_alias then
		if model_alias.drawtype == "entity" then
			def = reg_entities[model_alias.name]
			local init_props = def.initial_properties
			def.textures = init_props and init_props.textures or def.textures
			def.mesh = init_props and init_props.mesh or def.mesh
		else
			def = reg_items[model_alias.name]
		end
	end

	local tiles = def.tiles or def.textures or {}
	local t = {}

	for _, v in ipairs(tiles) do
		local _name

		if v.color then
			if is_num(v.color) then
				local hex = fmt("%02x", v.color)

				while #hex < 8 do
					hex = "0" .. hex
				end

				_name = fmt("%s^[multiply:%s", v.name,
					fmt("#%s%s", sub(hex, 3), sub(hex, 1, 2)))
			else
				_name = fmt("%s^[multiply:%s", v.name, v.color)
			end
		elseif v.animation then
			_name = fmt("%s^[verticalframe:%u:0", v.name, v.animation.frames_h or v.animation.aspect_h)
		end

		insert(t, _name or v.name or v)
	end

	while #t < 6 do
		insert(t, t[#t])
	end

	fs("model", data.inv_width + 6.6, data.yoffset + 0.05, 1.3, 1.3, "preview",
		def.mesh, concat(t, ","), "0,0", "true", "true",
		model_alias and model_alias.frames or "")
end

local function get_header(fs, data)
	local fav = is_fav(data.favs, data.query_item)
	local nfavs = #data.favs
	local star_x, star_y, size = data.inv_width + 0.3, data.yoffset + 0.2, 0.4

	if nfavs < i3.MAX_FAVS or (nfavs == i3.MAX_FAVS and fav) then
		local fav_marked = fmt("i3_fav%s.png", fav and "_off" or "")
		fs(fmt("style[fav;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			fmt("i3_fav%s.png", fav and "" or "_off"), fav_marked, fav_marked))
		fs("image_button", star_x, star_y, size, size, "", "fav", "")
		fs(fmt("tooltip[fav;%s]", fav and ES"Unmark this item" or ES"Mark this item"))
	else
		fs(fmt("style[nofav;fgimg=%s;fgimg_hovered=%s;fgimg_pressed=%s]",
			"i3_fav_off.png", PNG.cancel, PNG.cancel))
		fs("image_button", star_x, star_y, size, size, "", "nofav", "")
		fs(fmt("tooltip[nofav;%s]", ES"Cannot mark this item. Bookmark limit reached."))
	end

	fs("image_button", star_x + 0.05, star_y + 0.6, size, size, "", "exit", "")
	fs(fmt("tooltip[exit;%s]", ES"Back to item list"))

	local desc_lim, name_lim = 34, 35
	local desc = translate(data.lang_code, get_desc(data.query_item))
	      desc = ESC(desc)
	local tech_name = data.query_item
	local X = data.inv_width + 0.95
	local Y1 = data.yoffset + 0.47
	local Y2 = Y1 + 0.5

	if #desc > desc_lim then
		fs("tooltip", X, Y1 - 0.1, 5.7, 0.24, desc)
		desc = snip(desc, desc_lim)
	end

	if #tech_name > name_lim then
		fs("tooltip", X, Y2 - 0.1, 5.7, 0.24, tech_name)
		tech_name = snip(tech_name, name_lim)
	end

	fs"style_type[label;font=bold;font_size=20]"
	fs("label", X, Y1, desc)
	fs"style_type[label;font=mono;font_size=16]"
	fs("label", X, Y2, clr(colors.blue, tech_name))
	fs"style_type[label;font=normal;font_size=16]"

	local def = reg_items[data.query_item]
	local model_alias = model_aliases[data.query_item]

	if def.drawtype == "mesh" or model_alias then
		get_model_fs(fs, data, def, model_alias)
	else
		fs("item_image", data.inv_width + 6.8, data.yoffset + 0.17, 1.1, 1.1, data.query_item)
	end
end

local function get_export_fs(fs, data, is_recipe, is_usage, max_stacks_rcp, max_stacks_usg)
	local name = is_recipe and "rcp" or "usg"
	local show_export = (is_recipe and data.export_rcp) or (is_usage and data.export_usg)

	fs(fmt("style[export_%s;fgimg=%s;fgimg_hovered=%s]",
		name, fmt("%s", show_export and PNG.export_hover or PNG.export), PNG.export_hover))
	fs("image_button", data.inv_width + 7.35, data.yoffset + 0.2, 0.45, 0.45, "", fmt("export_%s", name), "")
	fs(fmt("tooltip[export_%s;%s]", name, ES"Quick crafting"))

	if not show_export then return end

	local craft_max = is_recipe and max_stacks_rcp or max_stacks_usg
	local stack_fs = (is_recipe and data.scrbar_rcp) or (is_usage and data.scrbar_usg) or 1

	if stack_fs > craft_max then
		stack_fs = craft_max

		if is_recipe then
			data.scrbar_rcp = craft_max
		elseif is_usage then
			data.scrbar_usg = craft_max
		end
	end

	fs(fmt("style[scrbar_%s;noclip=true]", name),
	   fmt("scrollbaroptions[min=1;max=%u;smallstep=1]", craft_max))
	fs("scrollbar", data.inv_width + 8.1, data.yoffset, 3, 0.35, "horizontal", fmt("scrbar_%s", name), stack_fs)
	fs("button", data.inv_width + 8.1, data.yoffset + 0.4, 3, 0.7,
		fmt("craft_%s", name), ES("Craft (×@1)", stack_fs))
end

local function get_rcp_extra(player, fs, data, panel, is_recipe, is_usage)
	fs"container[0,0.075]"
	local rn = panel.rcp and #panel.rcp

	if rn then
		local rcp_ok = is_recipe and panel.rcp[data.rnum].type == "normal"
		local usg_ok = is_usage and panel.rcp[data.unum].type == "normal"
		local max_stacks_rcp, max_stacks_usg = 0, 0
		local inv = player:get_inventory()

		if rcp_ok then
			max_stacks_rcp = get_stack_max(inv, data, is_recipe, panel.rcp[data.rnum])
		end

		if usg_ok then
			max_stacks_usg = get_stack_max(inv, data, is_recipe, panel.rcp[data.unum])
		end

		if is_recipe and max_stacks_rcp == 0 then
			data.export_rcp = nil
			data.scrbar_rcp = 1
		elseif is_usage and max_stacks_usg == 0 then
			data.export_usg = nil
			data.scrbar_usg = 1
		end

		if max_stacks_rcp > 0 or max_stacks_usg > 0 then
			get_export_fs(fs, data, is_recipe, is_usage, max_stacks_rcp, max_stacks_usg)
		end

		get_rcp_lbl(fs, data, panel, rn, is_recipe)
	else
		local lbl = is_recipe and ES"No recipes" or ES"No usages"
		fs("button", data.inv_width + 0.1, data.yoffset + (panel.height / 2) - 0.5, 7.8, 1, "no_rcp", lbl)
	end

	fs"container_end[]"
end

local function get_items_fs(fs, data, full_height)
	if compression_active(data) then
		local new = {}

		for i = 1, #data.items do
			local item = data.items[i]
			if not i3.compressed[item] then
				insert(new, item)
			end
		end

		data.items = new
	end

	local items = data.alt_items or data.items or {}
	local rows, lines = 8, 12
	local ipp = rows * lines
	local size = 0.85

	fs(fmt("box[%f,0.2;4.05,0.6;#bababa25]", data.inv_width + 0.3),
	   "set_focus[filter]",
	   fmt("field[%f,0.2;2.95,0.6;filter;;%s]", data.inv_width + 0.35, ESC(data.filter)),
	   "field_close_on_enter[filter;false]")

	fs("image_button", data.inv_width + 3.35, 0.35, 0.3,  0.3,  "", "cancel", "")
	fs("image_button", data.inv_width + 3.85, 0.32, 0.35, 0.35, "", "search", "")
	fs("image_button", data.inv_width + 5.27, 0.3,  0.35, 0.35, "", "prev_page", "")
	fs("image_button", data.inv_width + 7.45, 0.3,  0.35, 0.35, "", "next_page", "")

	data.pagemax = max(1, ceil(#items / ipp))

	fs("button", data.inv_width + 5.6, 0.14, 1.88, 0.7, "pagenum",
		fmt("%s / %u", clr(colors.yellow, data.pagenum), data.pagemax))

	if #items == 0 then
		local lbl = ES"No item to show"

		if next(i3.recipe_filters) and #i3.init_items > 0 and data.filter == "" then
			lbl = ES"Collect items to reveal more recipes"
		end

		fs("button", data.inv_width + 0.1, 3, 8, 1, "no_item", lbl)
	else
		local first_item = (data.pagenum - 1) * ipp

		for i = first_item, first_item + ipp - 1 do
			local item = items[i + 1]
			if not item then break end

			local _compressed = item:sub(1, 1) == "_"
			local name = _compressed and item:sub(2) or item

			local X = i % rows
			X -= (X * 0.045) + data.inv_width + 0.28

			local Y = round((i % ipp - X) / rows + 1, 0)
			Y -= (Y * 0.085) + 0.95

			insert(fs, fmt("item_image_button", X, Y, size, size, name, item, ""))

			if compressible(item, data) then
				local expand = data.expand == name

				fs(fmt("tooltip[%s;%s]", item, expand and ES"Click to hide" or ES"Click to expand"))
				fs"style_type[label;font=bold;font_size=20]"
				fs("label", X + 0.65, Y + 0.7, expand and "-" or "+")
				fs"style_type[label;font=normal;font_size=16]"
			end
		end
	end

	local _tabs = {"All", "Nodes", "Items"}
	local tab_len, tab_hgh = 1.8, 0.5

	for i, title in ipairs(_tabs) do
		local selected = i == data.itab
		fs(fmt([[style_type[image_button;fgimg=%s;fgimg_hovered=%s;noclip=true;
			font_size=16;textcolor=%s;content_offset=0;sound=i3_tab] ]],
		selected and PNG.tab_small_hover or PNG.tab_small,
		PNG.tab_small_hover, selected and "#fff" or "#ddd"))

		fs"style_type[image_button:hovered;textcolor=#fff]"
		fs("image_button", (data.inv_width - 0.65) + (i * (tab_len + 0.1)),
			full_height, tab_len, tab_hgh, "", fmt("itab_%u", i), title)
	end
end

local function get_favs(fs, data)
	fs("label", data.inv_width + 0.4, data.yoffset + 0.4, ES"Bookmarks")

	for i = 1, #data.favs do
		local item = data.favs[i]
		local X = data.inv_width - 0.7 + (i * 1.2)
		local Y = data.yoffset + 0.8

		if data.query_item == item then
			fs("image", X, Y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE, PNG.slot)
		end

		fs("item_image_button", X, Y, i3.ITEM_BTN_SIZE, i3.ITEM_BTN_SIZE, item, item, "")
	end
end

local function get_panels(player, data, fs, full_height)
	local _title   = {name = "title", height = 1.4}
	local _favs    = {name = "favs",  height = 2.23}
	local _items   = {name = "items", height = full_height}
	local _recipes = {name = "recipes", rcp = data.recipes, height = 4.045}
	local _usages  = {name = "usages",  rcp = data.usages,  height = 4.045}
	local panels

	if data.query_item then
		panels = {_title, _recipes, _usages, _favs}
	else
		panels = {_items}
	end

	for idx = 1, #panels do
		local panel = panels[idx]
		data.yoffset = 0

		if idx > 1 then
			for _idx = idx - 1, 1, -1 do
				data.yoffset = data.yoffset + panels[_idx].height + 0.1
			end
		end

		fs("bg9", data.inv_width + 0.1, data.yoffset, 7.9, panel.height, PNG.bg_full, 10)

		local is_recipe, is_usage = panel.name == "recipes", panel.name == "usages"

		if is_recipe or is_usage then
			get_rcp_extra(player, fs, data, panel, is_recipe, is_usage)
		elseif panel.name == "items" then
			get_items_fs(fs, data, full_height)
		elseif panel.name == "title" then
			get_header(fs, data)
		elseif panel.name == "favs" then
			get_favs(fs, data)
		end
	end
end

local function get_tabs_fs(player, data, fs, full_height)
	local tab_len, tab_hgh, c, over = 3, 0.5, 0
	local _tabs = copy(i3.tabs)

	for i, def in ipairs(i3.tabs) do
		if def.access and not def.access(player, data) then
			remove(_tabs, i)
		end
	end

	local shift = min(3, #_tabs)

	for i, def in ipairs(_tabs) do
		if not over and c > 2 then
			over = true
			c = 0
		end

		local btm = i <= 3

		if not btm then
			shift = #_tabs - 3
		end

		local selected = i == data.tab

		fs(fmt([[style_type[image_button;fgimg=%s;fgimg_hovered=%s;noclip=true;
			font_size=16;textcolor=%s;content_offset=0;sound=i3_tab] ]],
		selected and (btm and PNG.tab_hover or PNG.tab_hover_top) or (btm and PNG.tab or PNG.tab_top),
		btm and PNG.tab_hover or PNG.tab_hover_top, selected and "#fff" or "#ddd"))

		local X = (data.inv_width / 2) + (c * (tab_len + 0.1)) - ((tab_len + 0.05) * (shift / 2))
		local Y = btm and full_height or -tab_hgh

		fs"style_type[image_button:hovered;textcolor=#fff]"
		fs("image_button", X, Y, tab_len, tab_hgh, "", fmt("tab_%s", def.name), ESC(def.description))

		if true_str(def.image) then
			local desc = translate(data.lang_code, def.description)
			fs("style_type[image;noclip=true]")
			fs("image", X + (tab_len / 2) - ((#desc * 0.1) / 2) - 0.55,
				Y + 0.05, 0.35, 0.35, fmt("%s^\\[resize:16x16", def.image))
		end

		c++
	end
end

local function get_debug_grid(data, fs, full_height)
	fs("style_type[label;font_size=8;noclip=true]")
	local spacing, i = 0.2, 1

	for x = 0, data.inv_width + 8, spacing do
		fs("box", x, 0, 0.01, full_height, "#ff0")
		fs("label", x, full_height + 0.1, tostring(i))
		i++
	end

	i = 61

	for y = 0, full_height, spacing do
		fs("box", 0, y, data.inv_width + 8, 0.01, "#ff0")
		fs("label", -0.15, y, tostring(i))
		i -= 1
	end

	fs("box", data.inv_width / 2, 0, 0.01, full_height, "#f00")
	fs("box", 0, full_height / 2, data.inv_width, 0.01, "#f00")
	fs"style_type[label;font_size=16]"
end

local function make_fs(player, data)
	--local start = os.clock()

	local fs = setmetatable({}, {
		__call = function(t, ...)
			local args = {...}
			local elem = fs_elements[args[1]]

			if elem then
				insert(t, fmt(elem, select(2, ...)))
			else
				insert(t, concat(args))
			end
		end
	})

	data.inv_width = 10.23
	local full_height = 12

	local tab = i3.tabs[data.tab]

	fs(fmt("formspec_version[%u]size[%f,%f]no_prepend[]bgcolor[#0000]",
		i3.MIN_FORMSPEC_VERSION, data.inv_width + 8, full_height), styles)

	fs("bg9", 0, 0, data.inv_width, full_height, PNG.bg_full, 10)

	if tab then
		tab.formspec(player, data, fs)
	end

	get_panels(player, data, fs, full_height)

	if #i3.tabs > 1 then
		get_tabs_fs(player, data, fs, full_height)
	end

	--get_debug_grid(data, fs, full_height)
	--print("make_fs()", fmt("%.2f ms", (os.clock() - start) * 1000))
	--print("#fs elements", #fs)

	return concat(fs)
end

return make_fs, get_inventory_fs
