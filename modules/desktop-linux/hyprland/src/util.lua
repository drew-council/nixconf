local M = {}

function M.shell_quote(value)
	local str = tostring(value)
	return "'" .. str:gsub("'", [['"'"']]) .. "'"
end

function M.join_lines(items)
	return table.concat(items, "\n")
end

function M.capture(command)
	local handle = io.popen(command)
	if handle == nil then
		return nil
	end

	local output = handle:read("*a")
	local ok = handle:close()
	if not ok then
		return nil
	end

	return output
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
