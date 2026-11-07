local generated = require("nixconf.generated")

local systemd_env = table.concat({
	"dbus-update-activation-environment --systemd",
	"DISPLAY",
	"HYPRLAND_INSTANCE_SIGNATURE",
	"WAYLAND_DISPLAY",
	"XDG_CURRENT_DESKTOP",
	"XDG_SESSION_TYPE",
}, " ")

local startup_commands = {
	generated.commands.kwalletInit,
	"qs -c bar",
	"systemctl --user start hyprpolkitagent",
	"swaync",
	"wl-paste --type text --watch cliphist store",
	"wl-paste --type image --watch cliphist store",
	"udiskie",
	"nm-applet",
	"blueman-applet",
	"1password --silent",
	"pcloud",
	systemd_env
		.. " && systemctl --user stop hyprland-session.target && systemctl --user start hyprland-session.target",
}

hl.on("hyprland.start", function()
	for _, command in ipairs(startup_commands) do
		hl.exec_cmd(command)
	end
end)
