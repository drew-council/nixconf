local generated = require("nixconf.generated")
local util = require("nixconf.util")

local M = {}

local default_label = "default"
local headless = generated.monitor.tabletHeadless
local host_config = generated.monitor.hosts[generated.host]
local state = {
	active_profile = default_label,
}
local last_profile_request_id = nil
local monitor_settle_timer = nil

local function state_path()
	local runtime_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
	return runtime_dir .. "/hyprmonitor-state.lua"
end

local function profile_request_path()
	local runtime_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
	return runtime_dir .. "/hyprmonitor-profile-request"
end

local function load_state()
	local chunk = loadfile(state_path())
	if chunk == nil then
		return
	end

	local ok, loaded = pcall(chunk)
	if ok and type(loaded) == "table" then
		state.active_profile = loaded.active_profile or state.active_profile
	end
end

local function read_profile_request()
	local file = io.open(profile_request_path(), "r")
	if file == nil then
		return nil, nil
	end

	local request_id = file:read("*l")
	local label = file:read("*l")
	file:close()

	if label == nil then
		label = request_id
		request_id = label
	end

	if request_id == nil or request_id == "" or label == nil or label == "" then
		return nil, nil
	end

	return request_id, label
end

local function load_desired_profile()
	local request_id, label = read_profile_request()
	if label == nil then
		return
	end

	last_profile_request_id = request_id
	state.active_profile = label
end

local function save_state()
	local path = state_path()
	local file = io.open(path, "w")
	if file == nil then
		return
	end

	file:write("return {\n")
	file:write("  active_profile = " .. string.format("%q", state.active_profile) .. ",\n")
	file:write("}\n")
	file:close()
end

local function output_from_desc(desc)
	if desc:sub(1, 5) == "desc:" then
		return desc
	end
	return "desc:" .. desc
end

local function resolve_output(monitors, output_ref)
	local monitor = monitors[output_ref]
	if type(monitor) == "table" and monitor.desc ~= nil then
		return output_from_desc(monitor.desc)
	end
	return output_from_desc(output_ref)
end

local function monitor_names()
	local names = {}
	for name, _ in pairs(host_config.monitors or {}) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function profiles_by_label()
	local profiles = {}
	for key, profile in pairs(host_config.profiles or {}) do
		profile.key = key
		profile.label = key
		profiles[key] = profile
	end
	return profiles
end

local function get_profile(label)
	if label == default_label or label == nil then
		return nil
	end
	return profiles_by_label()[label]
end

local function is_valid_profile_label(label)
	return label == default_label or profiles_by_label()[label] ~= nil
end

local function profile_labels()
	local labels = { default_label }
	for label, _ in pairs(profiles_by_label()) do
		table.insert(labels, label)
	end
	table.sort(labels)
	return labels
end

local function default_enabled_outputs()
	local outputs = {}
	for _, key in ipairs(monitor_names()) do
		outputs[resolve_output(host_config.monitors, key)] = true
	end
	return outputs
end

local function profile_enabled_outputs(profile)
	if profile == nil then
		return default_enabled_outputs()
	end

	local outputs = {}
	for _, output_ref in ipairs(profile.enabledOutputs or {}) do
		outputs[resolve_output(host_config.monitors, output_ref)] = true
	end
	return outputs
end

local function profile_overrides(profile)
	if profile == nil or profile.monitorOverrides == nil then
		return {}
	end

	local resolved = {}
	for output_ref, overrides in pairs(profile.monitorOverrides) do
		resolved[resolve_output(host_config.monitors, output_ref)] = overrides
	end
	return resolved
end

local function stop_sunshine()
	-- Sunshine used to be launched as an untracked background process. Stop
	-- both units and any legacy process so an old instance cannot keep serving
	-- the wrong output after a profile switch or Lua config reload.
	util.run("systemctl --user stop sunshine-tablet.service sunshine.service >/dev/null 2>&1")
	util.run("pkill -KILL -x sunshine >/dev/null 2>&1")
end

local function apply_monitor(output, settings, overrides)
	local spec = {
		output = output,
		mode = overrides.mode or settings.mode,
		position = overrides.position or settings.position,
		scale = tostring(overrides.scale or settings.scale),
		disabled = false,
	}

	for key, value in pairs(settings) do
		if key ~= "mode" and key ~= "position" and key ~= "scale" then
			spec[key] = value
		end
	end
	for key, value in pairs(overrides) do
		if key ~= "mode" and key ~= "position" and key ~= "scale" then
			spec[key] = value
		end
	end

	hl.monitor(spec)
end

local function settle_monitor_layout()
	if monitor_settle_timer ~= nil then
		monitor_settle_timer:set_enabled(false)
	end

	monitor_settle_timer = hl.timer(function()
		-- Mapping a layer-shell surface makes Hyprland arrange every layer on
		-- that output. Poke each active physical output after the monitor rules
		-- settle, then immediately remove the transparent surfaces.
		local command = generated.commands.monitorLayoutPoke
		for _, monitor in ipairs(hl.get_monitors()) do
			if monitor.name ~= headless.name then
				command = command .. " " .. util.shell_quote(monitor.name)
			end
		end
		hl.exec_cmd(command)
	end, { timeout = 250, type = "oneshot" })
end

local function start_sunshine()
	for _ = 1, 30 do
		if hl.get_monitor(headless.name) ~= nil then
			-- The service forces wlr capture and targets the stable Wayland
			-- output name. This bypasses the XDG portal picker and cannot drift
			-- when physical outputs are enabled, disabled, or reordered.
			util.run("systemctl --user restart sunshine-tablet.service")
			return
		end
		util.run("sleep 0.1")
	end

	util.notify("hyprmonitor", "unable to find tablet headless output")
end

local function switch_audio(profile)
	local alsa_name = nil
	local card_name = nil
	local card_profile = nil
	if profile ~= nil then
		alsa_name = profile.defaultAudioOutputAlsaName
		card_name = profile.audioCardName
		card_profile = profile.audioCardProfile
	end
	if alsa_name == nil then
		alsa_name = host_config.defaultAudioOutputAlsaName
	end
	if alsa_name == nil then
		return
	end

	local command = generated.commands.switchaudio .. " --wait 120 --alsa-name " .. util.shell_quote(alsa_name)
	if card_name ~= nil and card_profile ~= nil then
		command = command
			.. " --card-name "
			.. util.shell_quote(card_name)
			.. " --card-profile "
			.. util.shell_quote(card_profile)
	end
	hl.exec_cmd(command)
end

function M.apply_profile(label)
	if host_config == nil then
		return
	end

	label = label or default_label
	if not is_valid_profile_label(label) then
		util.notify("hyprmonitor", "unknown monitor profile: " .. tostring(label))
		return
	end

	local profile = get_profile(label)
	local enabled_outputs = profile_enabled_outputs(profile)
	local overrides = profile_overrides(profile)

	stop_sunshine()

	for _, key in ipairs(monitor_names()) do
		local monitor = host_config.monitors[key]
		local output = resolve_output(host_config.monitors, key)
		if enabled_outputs[output] then
			apply_monitor(output, monitor.settings, overrides[output] or {})
		else
			hl.monitor({ output = output, disabled = true })
		end
	end

	if profile ~= nil and profile.useTablet then
		hl.monitor({
			output = headless.name,
			mode = tostring(math.floor(headless.width / headless.downsample)) .. "x" .. tostring(
				math.floor(headless.height / headless.downsample)
			),
			position = headless.position,
			scale = tostring(headless.scale),
			disabled = false,
		})
		start_sunshine()
	end

	state.active_profile = label
	save_state()
	settle_monitor_layout()
	switch_audio(profile)
end

function M.choose_profile()
	local labels = profile_labels()
	local result = util.capture(
		"printf %s "
			.. util.shell_quote(util.join_lines(labels))
			.. " | fuzzel --dmenu --index --prompt "
			.. util.shell_quote("Monitors> ")
	)
	if result == nil or result == "" then
		return
	end

	local index = tonumber(result:match("%d+"))
	if index == nil then
		util.notify("hyprmonitor", "fuzzel returned a non-numeric selection")
		return
	end

	local selected = labels[index + 1]
	if selected ~= nil then
		M.apply_profile(selected)
	end
end

function M.choose_profile_command()
	return generated.commands.monitorProfileSelector
end

local function poll_profile_request()
	local request_id, label = read_profile_request()
	if request_id == nil or request_id == last_profile_request_id then
		return
	end

	last_profile_request_id = request_id
	M.apply_profile(label)
end

if host_config ~= nil then
	load_state()
	load_desired_profile()
	M.apply_profile(state.active_profile)
	M.profile_request_timer = hl.timer(poll_profile_request, { timeout = 250, type = "repeat" })
end

return M
