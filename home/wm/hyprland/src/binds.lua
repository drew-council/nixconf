local generated = require("nixconf.generated")

local defaults = generated.defaults
local commands = generated.commands
local mod = "SUPER"
local launcher_timers = {}
local launcher_armed = false

---@enum NavAction
local NavAction = {
	Up = 0,
	Down = 1,
	Left = 2,
	Right = 3,
	Close = 4,
	NewTab = 5,
}

local nav_directions = {
	[NavAction.Up] = "up",
	[NavAction.Down] = "down",
	[NavAction.Left] = "left",
	[NavAction.Right] = "right",
}

local kitty_nav_keys = {
	[NavAction.Left] = "h",
	[NavAction.Right] = "l",
	[NavAction.Close] = "w",
	[NavAction.NewTab] = "t",
}

-- Any action while Super is held turns the launcher gesture into a chord.
local function bind(keys, dispatcher, opts)
	return hl.bind(keys, function()
		launcher_armed = false
		if type(dispatcher) == "function" then
			dispatcher()
		else
			hl.dispatch(dispatcher)
		end
	end, opts)
end

local function bind_exec(keys, command, opts)
	bind(keys, hl.dsp.exec_cmd(command), opts)
end

local function workspace_is_empty(workspace)
	return workspace == nil or #workspace:get_windows() == 0
end

local function cursor_is_on_desktop(monitor)
	local cursor = hl.get_cursor_pos()
	if cursor == nil then
		return false
	end

	local position = monitor.position
	local reserved = monitor.reserved
	local width = monitor.size.width / monitor.scale
	local height = monitor.size.height / monitor.scale

	return cursor.x >= position.x + reserved.left
		and cursor.x < position.x + width - reserved.right
		and cursor.y >= position.y + reserved.top
		and cursor.y < position.y + height - reserved.bottom
end

local function open_launcher_on_empty_desktop()
	local monitor = hl.get_monitor_at_cursor()
	if monitor == nil or not cursor_is_on_desktop(monitor) then
		return
	end

	if workspace_is_empty(monitor.active_workspace) and workspace_is_empty(monitor.active_special_workspace) then
		hl.dispatch(hl.dsp.exec_cmd("fuzzel"))
	end
end

local function run_workspace_launcher(directives, opts)
	opts = opts or {}
	local index = 1
	local initial_workspace = opts.restore and "previous" or nil

	local function step()
		launcher_timers[directives] = nil
		local directive = directives[index]
		if directive == nil then
			if initial_workspace ~= nil then
				hl.dispatch(hl.dsp.focus({ workspace = initial_workspace }))
			end
			return
		end

		hl.dispatch(hl.dsp.focus({ workspace = directive.workspace }))
		hl.dispatch(hl.dsp.exec_cmd(directive.command))
		index = index + 1

		if directives[index] ~= nil or initial_workspace ~= nil then
			launcher_timers[directives] = hl.timer(step, { timeout = directive.delay or 250, type = "oneshot" })
		end
	end

	step()
end

local function active_window_class()
	local window = hl.get_active_window()
	if window == nil then
		return nil
	end

	return window.class
end

local function send_active_keypress(key)
	local target = "activewindow"
	hl.dispatch(hl.dsp.send_key_state({ mods = mod, key = key, state = "down", window = target }))
	hl.dispatch(hl.dsp.send_key_state({ mods = mod, key = key, state = "up", window = target }))
end

local function navigate(keys, action)
	return bind(keys, function()
		local kitty_key = kitty_nav_keys[action]
		if active_window_class() == "kitty" and kitty_key ~= nil then
			send_active_keypress(kitty_key)
			return
		end

		local direction = nav_directions[action]
		if direction ~= nil then
			hl.dispatch(hl.dsp.focus({ direction = direction }))
		elseif action == NavAction.Close then
			hl.dispatch(hl.dsp.window.close())
		end
	end)
end

bind_exec(mod .. " + RETURN", defaults.tty)
bind_exec(mod .. " + E", defaults.fileManager)
bind_exec(mod .. " + B", defaults.browser)
bind_exec(mod .. " + R", commands.voxtype .. " record toggle")
bind_exec(mod .. " + SHIFT + R", commands.voxtype .. " record cancel")
bind_exec(mod .. " + SHIFT + B", defaults.browser .. " --private-window duckduckgo.com")
bind_exec(mod .. " + P", "hyprpicker -a")
bind_exec(mod .. " + EQUAL", defaults.calculator)

bind_exec(mod .. " + Z", defaults.editor)
bind_exec(mod .. " + N", defaults.editor .. " " .. defaults.home .. "/nixconf")
if generated.personal then
	bind(mod .. " + G", function()
		run_workspace_launcher({
			{ workspace = 2, command = "steam" },
			{ workspace = 3, command = defaults.browser },
			{ workspace = 9, command = "vesktop" },
		})
	end)
end
navigate(mod .. " + T", NavAction.NewTab)

hl.bind(mod .. " + SUPER_L", function()
	launcher_armed = true
end, { non_consuming = true })
hl.bind(mod .. " + SUPER_L", function()
	if launcher_armed then
		hl.dispatch(hl.dsp.exec_cmd("fuzzel"))
	end
	launcher_armed = false
end, { release = true })
-- Also disarm for keys that do not have their own binding.
hl.define_submap("launcher-guard", function()
	hl.bind("catchall", function()
		launcher_armed = false
	end, { ignore_mods = true, non_consuming = true, submap_universal = true })
end)

hl.bind("mouse:273", open_launcher_on_empty_desktop, { click = true, non_consuming = true })
bind_exec(mod .. " + V", "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy")
bind_exec(mod .. " + SLASH", "bemoji -t")

bind_exec(mod .. " + COMMA", "playerctl previous")
bind_exec(mod .. " + PERIOD", "playerctl next")
bind_exec(mod .. " + SPACE", "playerctl play-pause")

navigate(mod .. " + W", NavAction.Close)
bind(mod .. " + SHIFT + W", hl.dsp.window.close())
bind(mod .. " + F", hl.dsp.window.float({ action = "toggle" }))
bind(mod .. " + SHIFT + M", hl.dsp.window.fullscreen())
bind_exec(mod .. " + M", commands.monitorProfileSelector)

navigate(mod .. " + left", NavAction.Left)
navigate(mod .. " + H", NavAction.Left)
navigate(mod .. " + right", NavAction.Right)
navigate(mod .. " + L", NavAction.Right)
navigate(mod .. " + up", NavAction.Up)
navigate(mod .. " + K", NavAction.Up)
navigate(mod .. " + down", NavAction.Down)
navigate(mod .. " + J", NavAction.Down)

bind(mod .. " + ALT + left", hl.dsp.window.resize({ x = -80, y = 0, relative = true }))
bind(mod .. " + ALT + H", hl.dsp.window.resize({ x = -80, y = 0, relative = true }))
bind(mod .. " + ALT + right", hl.dsp.window.resize({ x = 80, y = 0, relative = true }))
bind(mod .. " + ALT + L", hl.dsp.window.resize({ x = 80, y = 0, relative = true }))
bind(mod .. " + ALT + up", hl.dsp.window.resize({ x = 0, y = -60, relative = true }))
bind(mod .. " + ALT + K", hl.dsp.window.resize({ x = 0, y = -60, relative = true }))
bind(mod .. " + ALT + down", hl.dsp.window.resize({ x = 0, y = 60, relative = true }))
bind(mod .. " + ALT + J", hl.dsp.window.resize({ x = 0, y = 60, relative = true }))

bind(mod .. " + Tab", function()
	hl.dispatch(hl.dsp.window.cycle_next())
	hl.dispatch(hl.dsp.window.bring_to_top())
end)

for workspace = 1, 10 do
	local key = tostring(workspace % 10)
	bind(mod .. " + " .. key, hl.dsp.focus({ workspace = workspace, on_current_monitor = true }))
	bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

bind(mod .. " + CONTROL + H", hl.dsp.focus({ workspace = "e-1" }))
bind(mod .. " + CONTROL + L", hl.dsp.focus({ workspace = "e+1" }))
bind(mod .. " + CONTROL + left", hl.dsp.focus({ workspace = "e-1" }))
bind(mod .. " + CONTROL + right", hl.dsp.focus({ workspace = "e+1" }))

bind(mod .. " + SHIFT + H", hl.dsp.window.move({ workspace = "e-1" }))
bind(mod .. " + SHIFT + L", hl.dsp.window.move({ workspace = "e+1" }))
bind(mod .. " + SHIFT + left", hl.dsp.window.move({ workspace = "e-1" }))
bind(mod .. " + SHIFT + right", hl.dsp.window.move({ workspace = "e+1" }))

bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

bind_exec("XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
bind_exec("XF86AudioRaiseVolume", "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+", { repeating = true })
bind_exec("XF86AudioLowerVolume", "wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-", { repeating = true })
bind_exec("XF86MonBrightnessUp", "brightnessctl s +5%", { repeating = true })
bind_exec("XF86MonBrightnessDown", "brightnessctl s 5%-", { repeating = true })
bind_exec("XF86AudioPlay", "playerctl play-pause")
bind_exec("XF86AudioPause", "playerctl play-pause")
bind_exec("XF86AudioNext", "playerctl next")
bind_exec("XF86AudioPrev", "playerctl previous")

bind_exec("PRINT", "hyprshot -z -m region")
bind_exec(mod .. " + SHIFT + S", "hyprshot -z -m region")
bind_exec(mod .. " + CONTROL + S", "hyprshot -z -m output")
bind_exec(mod .. " + PRINT", "hyprshot -z -m output")
bind_exec(mod .. " + SHIFT + PRINT", "hyprshot -z -m window")
