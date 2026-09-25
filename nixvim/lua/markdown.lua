-- Wrap Markdown at whitespace instead of punctuation within words
local default_breakat = vim.o.breakat
local markdown_wrap_group = vim.api.nvim_create_augroup("MarkdownWrap", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
	group = markdown_wrap_group,
	pattern = "*",
	callback = function()
		if vim.bo.filetype == "markdown" then
			vim.opt_local.linebreak = true
			vim.o.breakat = " \t"
		else
			vim.o.breakat = default_breakat
		end
	end,
})

vim.api.nvim_create_autocmd("BufLeave", {
	group = markdown_wrap_group,
	pattern = "*",
	callback = function()
		if vim.bo.filetype == "markdown" then
			vim.o.breakat = default_breakat
		end
	end,
})

-- Pb command for Markdown buffers: wrap clipboard in fenced code block
local pb_group = vim.api.nvim_create_augroup("MarkdownPb", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
	group = pb_group,
	pattern = "markdown",
	callback = function(args)
		vim.api.nvim_buf_create_user_command(args.buf, "Pb", function(opts)
			local text = vim.fn.getreg("+")
			if text == "" then
				text = vim.fn.getreg("*")
			end
			if text == "" then
				vim.api.nvim_echo({ { "pb: clipboard (+ register) is empty", "WarningMsg" } }, true, {})
				return
			end
			local block = vim.split(text, "\r?\n")
			while #block > 0 and block[#block] == "" do
				table.remove(block)
			end
			local lines = { "", "```" .. (opts.args or "") }
			for _, line in ipairs(block) do
				lines[#lines + 1] = line
			end
			lines[#lines + 1] = "```"
			lines[#lines + 1] = ""
			local row = vim.api.nvim_win_get_cursor(0)[1]
			vim.api.nvim_buf_set_lines(args.buf, row, row, false, lines)
			vim.api.nvim_win_set_cursor(0, { row + #lines, 0 })
		end, { nargs = "?", desc = "Wrap the clipboard in a Markdown code block below the current line" })
	end,
})

vim.cmd.cnoreabbrev("pb", "Pb")
