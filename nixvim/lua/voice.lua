-- Voice command: dictate with the voxtype daemon into the buffer that ran it.
-- The daemon writes the transcript to a file rather than typing it, so
-- focus can wander to other windows while recording.
local function voxtype(args)
	return vim.system(vim.list_extend({ "voxtype" }, args), { text = true })
end

local function voice_insert(buf, pos, text)
	if not vim.api.nvim_buf_is_valid(buf) then
		vim.notify("voice: target buffer is gone", vim.log.levels.WARN)
		return
	end
	local lines = vim.split(text, "\n", { plain = true })
	local row, col = pos[1] - 1, pos[2]
	vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)
	local win = vim.fn.bufwinid(buf)
	if win ~= -1 then
		local last = #lines == 1 and col + #lines[1] or #lines[#lines]
		vim.api.nvim_win_set_cursor(win, { row + #lines, math.max(last - 1, 0) })
	end
end

vim.api.nvim_create_user_command("Voice", function()
	if vim.fn.executable("voxtype") == 0 then
		vim.notify("voice: voxtype is not on PATH", vim.log.levels.ERROR)
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	if not vim.bo[buf].modifiable then
		vim.notify("voice: buffer is not modifiable", vim.log.levels.ERROR)
		return
	end
	local status = vim.trim(voxtype({ "status" }):wait().stdout or "")
	if status ~= "idle" then
		vim.notify("voice: voxtype is busy (" .. status .. ")", vim.log.levels.ERROR)
		return
	end

	-- Insert after the cursor, like `a`, or at column 0 on an empty line.
	local pos = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	if #line > 0 then
		pos[2] = pos[2] + #vim.fn.strcharpart(line:sub(pos[2] + 1), 0, 1)
	end

	local file = vim.fn.tempname() .. ".txt"
	local start = voxtype({ "record", "start", "--file=" .. file }):wait()
	if start.code ~= 0 then
		vim.notify("voice: " .. vim.trim(start.stderr or ""), vim.log.levels.ERROR)
		return
	end

	local prompt = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(prompt, 0, -1, false, { " Recording… <Enter> transcribe, <Esc> cancel " })
	local width = vim.api.nvim_strwidth(vim.api.nvim_buf_get_lines(prompt, 0, 1, false)[1])
	local float = vim.api.nvim_open_win(prompt, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - 3) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
		title = " voice ",
		title_pos = "center",
	})

	local done = false
	local function finish(stop)
		if done then
			return
		end
		done = true
		if vim.api.nvim_win_is_valid(float) then
			vim.api.nvim_win_close(float, true)
		end
		if not stop then
			voxtype({ "record", "cancel" }):wait()
			os.remove(file)
			vim.notify("voice: cancelled")
			return
		end
		vim.notify("voice: transcribing…")
		vim.system(
			{ "voxtype", "record", "stop", "--wait" },
			{ text = true },
			vim.schedule_wrap(function(result)
				local handle = io.open(file, "r")
				local text = handle and handle:read("*a") or ""
				if handle then
					handle:close()
				end
				os.remove(file)
				text = text:gsub("\n$", "")
				if result.code == 0 and text ~= "" then
					voice_insert(buf, pos, text)
					vim.notify("voice: inserted transcription")
				elseif result.code == 3 or (result.code == 0 and text == "") then
					vim.notify("voice: nothing to transcribe", vim.log.levels.WARN)
				else
					local err = vim.trim((result.stderr or "") .. (result.stdout or ""))
					vim.notify(
						"voice: transcription failed (exit " .. result.code .. "): " .. err,
						vim.log.levels.ERROR
					)
				end
			end)
		)
	end

	local opts = { buffer = prompt, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		finish(true)
	end, opts)
	vim.keymap.set("n", "<Esc>", function()
		finish(false)
	end, opts)
	vim.keymap.set("n", "q", function()
		finish(false)
	end, opts)
	-- Leaving the prompt any other way must not leave the daemon recording.
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = prompt,
		once = true,
		callback = function()
			finish(false)
		end,
	})
end, { desc = "Dictate with voxtype into the current buffer" })

-- `:v` is `:vglobal`, so only expand a bare `:v` (then Enter or Space).
vim.keymap.set("ca", "v", function()
	local bare = vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == "v"
	return (bare and (vim.v.char == "\r" or vim.v.char == " ")) and "Voice" or "v"
end, { expr = true })
vim.cmd.cnoreabbrev("voice", "Voice")
