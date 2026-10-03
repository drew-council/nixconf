local generated = require("nixconf.generated")

local M = {}

local gaps_in = generated.laptop and 0 or 5
local gaps_out = generated.laptop and 0 or 10
local rounding = generated.laptop and 0 or 14

hl.window_rule({
	name = "steam-big-picture-fullscreen",
	match = {
		class = "^steam$",
		title = "^Steam Big Picture Mode$",
	},
	fullscreen = true,
})

-- agent-browser sets this class through its managed Chrome launch arguments.
hl.window_rule({
	name = "agent-browser-workspace",
	match = {
		initial_class = "^agent-browser$",
	},
	workspace = "6 silent",
})

hl.config({
	xwayland = {
		force_zero_scaling = true,
	},
	general = {
		gaps_in = gaps_in,
		gaps_out = gaps_out,
		col = {
			active_border = {
				colors = {
					generated.catppuccin.mauve,
					generated.catppuccin.pink,
				},
				angle = 90,
			},
		},
	},
	decoration = {
		rounding = rounding,
	},
	input = {
		kb_layout = "us",
		follow_mouse = 1,
		mouse_refocus = false,
		sensitivity = -0.2,
		accel_profile = "flat",
		numlock_by_default = true,
		kb_options = "caps:escape",
		touchpad = {
			natural_scroll = true,
		},
	},
	cursor = {
		no_hardware_cursors = true,
		inactive_timeout = 5,
	},
	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
	},
	misc = {
		disable_hyprland_logo = true,
		middle_click_paste = false,
	},
})

if generated.nvidia then
	hl.env("LIBVA_DRIVER_NAME", "nvidia")
	hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
	hl.env("WLR_NO_HARDWARE_CURSORS", "1")
	hl.env("OGL_DEDICATED_HW_STATE_PER_CONTEXT", "ENABLE_ROBUST")
end

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

function M.set_gaps(enabled)
	hl.config({
		general = {
			gaps_in = enabled and gaps_in or 0,
			gaps_out = enabled and gaps_out or 0,
		},
		decoration = {
			rounding = enabled and rounding or 0,
		},
	})
end

return M
