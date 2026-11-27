local M = {}

function M.shell_quote(value)
	local str = tostring(value)
	return "'" .. str:gsub("'", [['"'"']]) .. "'"
end

function M.run(command)
	os.execute(command)
end

function M.notify(summary, body)
	local command = "notify-send " .. M.shell_quote(summary)
	if body ~= nil and body ~= "" then
		command = command .. " " .. M.shell_quote(body)
	end
	hl.exec_cmd(command)
end

return M
