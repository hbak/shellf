-- TODO
-- - header block:
--   - in-line and block comments
--     - block comments might be tricky
--   - vim operator
-- - shellExecuteWithColor()'s python script should return byte codes, there shouldn't be any string substitutions
-- - multiline:
--   - shell commands (use backslash?)
--   - postRunDirectives
--   - block comments
--   - postRunFunctionBody
--   - you may need to implement some kind of parser.   comments and $> could be inside quotes, invalidating them
--   - header lua/vim functions


local thisPluginName = 'Shellf'

local executionBlockDelimiters = { '--' }
local commentStrings = { '#', '//' }
local postDirectiveStrings = { '$>' }
local colorizeExCommand = 'BaleiaColorize'
local shellCmd = '/bin/bash'

local function print(...)
	local args = {...}
	local fullString = '['..thisPluginName..']'
	for _, arg in ipairs(args) do
		fullString = fullString .. ' ' .. tostring(arg)
	end
  _G.print(fullString)
end

local function isLineBlockDelimiter(line)
	return table.contains(executionBlockDelimiters, line)
end

local function getLine(lineNo)
	local curLine = vim.fn.trim(vim.fn.getline(lineNo))
	return curLine
end

local function shellExecuteSimple(stringToEval)
	local handle = assert(io.popen(stringToEval))
	local result = handle:read("*a")
	handle:close()
	return result
end

local function shellExecuteWithColor(command, context)
	local shellfCommandFile = '/tmp/shellf_in.sh'
	local file = assert(io.open(shellfCommandFile, "w"))
	for k, v in pairs(context) do
		file:write(string.format("%s=%s\n", k, v))
	end
	file:write(command)
	file:close()
	local pyscript = string.format([[<<EOF 
import pexpect
# (command_output, exitstatus) = pexpect.run('''[percent]s '[percent]s' | xargs echo''', withexitstatus=1)
(command_output, exitstatus) = pexpect.run('%s %s', withexitstatus=1)
print(command_output)
# print(exitstatus)
]], shellCmd, shellfCommandFile)
	local pyOutput = vim.api.nvim_exec('py3 ' .. pyscript, true)
	local transformedOutput = string.sub(pyOutput, 3, #pyOutput - 1)
	local gsubTransformations = { ["\\x1b"]='', ["\\r\\n"]= '\n', ["\\r"]='', ["\\n"]='\n', ["\\t"]='\t' }
	for k, v in pairs(gsubTransformations) do
		transformedOutput = string.gsub(transformedOutput, k, v)
	end
	return transformedOutput
end

-- returns last line delimiter as well as entire header block
local function getHeaderBlock()
	local lineToCheck = 1
	local counter = 0
	while not isLineBlockDelimiter(getLine(lineToCheck)) and lineToCheck <= vim.fn.line('$') and counter < 9999 do
		counter = counter + 1
		lineToCheck = lineToCheck + 1
	end
	local buffer = vim.fn.bufnr("%")
	local lines = vim.api.nvim_buf_get_lines(buffer, 0, lineToCheck, true)
	return { lastLine=lineToCheck, lines=lines }
end

local function processHeaderLinesToContextTable(lines)
	local possibleOps = {'=', 'lua', 'vim', 'sh'}
	local context = {}
	for _, line in ipairs(lines) do
		if vim.fn.trim(line) == '' then
			goto continue
		end
		local splitSpace = string.split(line, ' ')
		-- local splitEquals = string.split(line, '=')
		local lhs = splitSpace[1]
		local op = splitSpace[2]
		if op == nil then
			error('header block has an invalid line: '..line)
		elseif not table.contains(possibleOps, op) then
			error('header block has an invalid operator: ' .. op..'.  Possible operators are: '..table.concat(possibleOps, ', '))
		end
		local rhs = table.concat(table.slice(splitSpace, 3, #splitSpace), ' ')
		if op == '=' then
			context[lhs] = rhs
			-- todo: check for $ char and expand them from shell env and also prior vars
			-- https://stackoverflow.com/questions/4181703/how-to-concatenate-string-variables-in-bash
		elseif op == 'sh' then
			context[lhs] = shellExecuteSimple(rhs)
		elseif op == 'lua' then
			local f = assert(load(rhs))
			context[lhs] = f()
			-- todo: implement "vim"
		end
	end
	::continue::
	return context
end

local function getExecutionBlock(lineNo, headerBlockEndLine)
	if lineNo == nil then
		lineNo = vim.fn.line('.')
	end

	local function checkDirection(startLineNo, direction)
		local lineToCheck = startLineNo
		local boundary

		if direction == 'up' then
			boundary = headerBlockEndLine - 1
		else
			boundary = vim.fn.line('$') + 1
			lineToCheck = lineToCheck + 1
		end
		local counter = 0

		while not isLineBlockDelimiter(getLine(lineToCheck)) and lineToCheck ~= boundary and counter < 9999 do
			counter = counter + 1
			if direction == 'up' then
				lineToCheck = lineToCheck - 1
			else
				lineToCheck = lineToCheck + 1
			end
		end
		if lineToCheck == boundary then
			if direction == 'up' then
				lineToCheck = headerBlockEndLine + 1
			else
				lineToCheck = vim.fn.line('$')
			end
		end
		return lineToCheck
	end

	local topBoundary = checkDirection(lineNo, 'up')
	local bottomBoundary = checkDirection(lineNo, 'down')

	local buffer = vim.fn.bufnr("%")
	local lines = vim.api.nvim_buf_get_lines(buffer, topBoundary, bottomBoundary, true)

	for _, delim in ipairs(executionBlockDelimiters) do
		if lines[1] == delim then
			table.remove(lines, 1)
		elseif lines[#lines] == delim then
			table.remove(lines, #lines)
		end
	end

	for _, comment in ipairs(commentStrings) do
		for idx, line in ipairs(lines) do
			local trimmed = vim.fn.trim(line)
			if string.sub(trimmed, 1, #comment) == comment or trimmed == '' then
				lines[idx] = nil
			end
		end
	end

	return lines
end

-- local metaCommandInvalidators = { { open='\'', close='\''}, { open='"', close='"' } }

-- this function is awful.  I think I shouldn't support inline comments
-- left to right:  find a commentStarter string in the line
-- if there is an unclosed, unescaped ' or " before the commentStarter, look in the comment for an unclosed, unescaped ' or "
-- if there is no closing ' or " in the comment candidate, then it's a comment
-- otherwise, continue and look for next commentStarter string

-- local function stripInlineComment(line)
--   local lastCommentPosition
--   for i = #line, 1 do
--     for _, commentString in commentStrings do
--       if #line - i >= #commentString
--         if string.sub(#line, i, i+#commentString) == commentString then

--         end
--       end
--     end
--   end
-- end

local function isCharacterEscaped(string, pos)
	if pos == 1 then
		return false
	elseif string[pos - 1] == '\\' then
		return true
	end
	return false
end

-- -- need to follow same idea as comments.  $> is my chosen post process delimiter.  Unclosed quotes should be the determinant
-- local function separatePostRunDirectives(line)
--   local invalidatorStates = {}
--   for idx, _ in ipairs(metaCommandInvalidators) do
--     invalidatorStates[idx] = {on=false}
--   end
--   -- TODO: be able to process multi-char invalidators (but when do they ever exist?  perhaps '''? )
--   for lineCounter=1, #line do
--     local thisCharHandled = false
--     for invalidatorIdx, invalidator in ipairs(metaCommandInvalidators) do
--       if line[lineCounter] == invalidator['open'] and not isCharacterEscaped(line, lineCounter) then
--         invalidatorStates[invalidatorIdx].on = true
--         thisCharHandled = true
--       elseif line[lineCounter] == invalidator['close'] and not isCharacterEscaped(line, lineCounter) then
--         invalidatorStates[invalidatorIdx].on = false
--         thisCharHandled = true
--       end
--     end
--     if not thisCharHandled then
--       local combinedInvalidatorState = true
--       for _, invalidatorState in invalidatorStates do
--         combinedInvalidatorState = combinedInvalidatorState and invalidatorState
--       end
--       -- TODO check contents of directive for dangling invalidator
--       -- or different approach:  split string by postRunDirective
--       --	case 2 pieces:  if left and right both have dangling, then it's not a directive (i.e. $> is enclosed in quotes)
--       --	case 3 pieces:  iterate pieces left to right.  If all left compositely dangling and all right is compositely closed
--       --		all right is the directive string
--       if not combinedInvalidatorState then
--         for _, postDirectiveString in ipairs(postDirectiveStrings) do
--           local potentialPostDirectiveStart = lineCounter - #postDirectiveString
--           if lineCounter > #postDirectiveString and
--             string.sub(line, potentialPostDirectiveStart, #lineCounter) == postDirectiveString and
--             not isCharacterEscaped(line, potentialPostDirectiveStart)
--           then
--             if #line > lineCounter then
--               return {
--                 postRunDirectives=vim.fn.trim(string.sub(line, #lineCounter, #line)),
--                 trimmedLine=vim.fn.trim(string.sub(line, 1, potentialPostDirectiveStart - 1))
--               }
--             end
--           end
--         end
--       end
--     end
--   end
--   return {
--     trimmedLine = vim.fn.trim(line)
--   }
-- end

local function separatePostRunDirectives(line)
	for _, postDirectiveString in ipairs(postDirectiveStrings) do
		local split = string.split(line, postDirectiveString)
		if #split > 1 then
			return {
				command = vim.fn.trim(split[1]),
				postRunDirectives = vim.fn.trim(table.concat(table.slice(split, 2, #split)))
			}
		end
	end
	return { command = vim.fn.trim(line) }
end


-- basically, separate command from postRunDirectives
local function processCommandLines(lines)
	local commandObjs = {}
	for _, line in pairs(lines) do
		-- stripInlineComment(line)
		local postRunSeparated = separatePostRunDirectives(line)
		commandObjs[#commandObjs + 1] = postRunSeparated
	end
	return commandObjs
end

local bracketablePostRunDirectives = { 'vs', 'sp', 'fl', 'vt' } -- floating win, virtualtext
local singletonDirectives = { '@' }
local directiveDelimiter = ' '
local function parsePostRunDirectives(directivesString, parsedDirectiveAggregator)
	-- there's no other way to extract vs{...} and sp{...}.   Have to scan string left to right
	for i=2, #directivesString do
		-- step one: strip out known bracketable directives
		for _, directive in ipairs(bracketablePostRunDirectives) do
			local charBeforeDirective = i - #directive

			if i >= #directive and
				(i == #directive or directivesString:sub(charBeforeDirective, charBeforeDirective) == directiveDelimiter) and
				-- potential directive under cursor i is first directive of directiveString or comes after a delimiter (space),
				-- all meaning that cursor i is potentially over the last character of a directive
				string.sub(directivesString, i - #directive + 1, i) == directive
			then
				-- directive begin
				local startCodeBlockIndex = 0
				local endCodeBlockIndex = 0
				local modifier = ''
				local directiveEndIndex = i+1
				for j=i+1, #directivesString do
					if directivesString:sub(j, j) == directiveDelimiter then
						directiveEndIndex = j - 1
						break
					elseif directivesString:sub(j, j) == '{' then
						startCodeBlockIndex = j
					elseif startCodeBlockIndex > 0 and directivesString:sub(j, j) == '}' then
						endCodeBlockIndex = j
						directiveEndIndex = j
						break
					else
						if startCodeBlockIndex == 0 then
							modifier = modifier..directivesString:sub(j, j)
							directiveEndIndex = j
						end
					end
				end

				local parsedDirective = { directive=directive }
				if #modifier > 0 then
					parsedDirective.modifier = modifier
				end
				if startCodeBlockIndex > 0 and endCodeBlockIndex > 0 then
					parsedDirective.codeBlock = vim.fn.trim(string.sub(directivesString, startCodeBlockIndex, endCodeBlockIndex), '{}')
				end

				parsedDirectiveAggregator[#parsedDirectiveAggregator + 1] = parsedDirective

				local preDirective = string.sub(directivesString, 1, i - #directive)
				local postDirective = string.sub(directivesString, directiveEndIndex + 1, #directivesString)
				local directivesStringWithBracketedDirectiveRemoved = preDirective..postDirective
				return parsePostRunDirectives(directivesStringWithBracketedDirectiveRemoved, parsedDirectiveAggregator)
			end
		end
	end
	-- at this point all bracketed directives are parsed out
	local singletonDirectivePossibilities = string.split(directivesString, directiveDelimiter)
	for _, possibleDirective in ipairs(singletonDirectivePossibilities) do
		for _, directive in ipairs(singletonDirectives) do
			if string.sub(possibleDirective, 1, #directive) == directive then
				local parsedDirective = { directive=directive }
				if #possibleDirective > #directive then
					parsedDirective.modifier = string.sub(possibleDirective, #directive + 1)
				end
				parsedDirectiveAggregator[#parsedDirectiveAggregator + 1] = parsedDirective
			end
		end
	end

	return parsedDirectiveAggregator
end

local function handlePostRunDirectives(commandObj, priorViewState)
	local postRunDirectives = {{directive="vs"}} -- modifier = '', codeBlock=''

	if commandObj.postRunDirectives ~= nil and #commandObj.postRunDirectives > 0 then
		postRunDirectives = parsePostRunDirectives(commandObj.postRunDirectives, {})
	end

	local newViewState = {}
	local viewStateChanges = {
		vs = false,
		sp = false
	}
	for _, postRunDirective in pairs(postRunDirectives) do
		local firstTwoLetters = string.sub(postRunDirective.directive, 1, 2)
	  if table.contains({'vs', 'sp'}, firstTwoLetters) then
			if priorViewState[firstTwoLetters] ~= nil then
				for _, vertBuffer in pairs(priorViewState[firstTwoLetters]) do
					vim.api.nvim_buf_delete(vertBuffer.bufId, {force=true})
				end
			end
			viewStateChanges[firstTwoLetters] = true
			if newViewState[firstTwoLetters] == nil then
				newViewState[firstTwoLetters] = {}
			end

			if firstTwoLetters == 'vs' then
				vim.cmd('bot vsplit')
			else
				vim.cmd('bot split')
			end
			local newWin = vim.api.nvim_get_current_win()
			local newBuf = vim.api.nvim_create_buf(true, true)
			vim.api.nvim_buf_set_keymap(newBuf, 'n', 'q', '<C-w>q', { noremap = true } )
			vim.api.nvim_buf_set_keymap(newBuf, 'n', '<Esc>', '<C-w>q', { noremap = true } )
			vim.api.nvim_buf_set_keymap(newBuf, 'n', '<C-[>', '<C-w>q', { noremap = true } )
			newViewState[firstTwoLetters][#newViewState[firstTwoLetters]] = { winId=newWin, bufId=newBuf}

			vim.api.nvim_win_set_buf(newWin, newBuf)
			local pyOutputLines = string.split(commandObj.output, '\n')
			vim.api.nvim_buf_set_lines(newBuf, 0, 0, true, pyOutputLines)

			vim.fn.win_execute(newWin, colorizeExCommand)
			if postRunDirective.codeBlock ~= nil then
				local ok, stuff = pcall(vim.fn.win_execute, newWin, 'lua '..postRunDirective.codeBlock)
				if not ok then
					vim.api.nvim_buf_set_lines(newBuf, 0, 0, true, {'there was an error in this code block:', postRunDirective.codeBlock, ' ', stuff, ' '})
				end
			end
		elseif postRunDirective.directive == '@' then
			-- TODO: steal the code from Baleia and strip out term color codes
			vim.fn.setreg(postRunDirective.modifier, commandObj.output)
		else
			print('unknown post run directive: ', postRunDirective)
		end
	end
	for viewStateElement, isChanged in pairs(viewStateChanges) do
		if not isChanged then
			newViewState[viewStateElement] = priorViewState[viewStateElement]
		end
	end
	return newViewState

end

local viewState = {}
function Shellf()
	local headerBlockInfo = getHeaderBlock()
	local context = processHeaderLinesToContextTable(table.slice(headerBlockInfo.lines, 1, #headerBlockInfo.lines -1))
	local defaultContext = { PAGER='cat' }
	for k, v in pairs(defaultContext) do
		if context[k] == nil then
			context[k] = v
		end
	end


	local executionBlock = getExecutionBlock(nil, headerBlockInfo.lastLine)
	-- TODO: 
	-- 1.  separate lines (that don't end with \) into separate commands, execute them separately, (or && join them?)  and join the results
	local commandLines = executionBlock
	local commandObjs = processCommandLines(commandLines)
	for _, commandObj in ipairs(commandObjs) do
		commandObj.output = shellExecuteWithColor(commandObj.command, context)
		viewState = handlePostRunDirectives(commandObj, viewState)
	end
end


-- next todos:
-- "host block", with custom operators.
-- - HOST = http://test.com
-- - HOST lua return $HOST .. '/path'
-- - HOST vim ...
-- - HOST sh|bash ...
-- - HOST() { return $API_HOST }
-- 
-- think about how you'd like to implement output splitting into different windows
--	- named functions that take in strings and perform regex splits
--	- a function that "finds" json and extracts + pretty-prints it
--
--	make a hotkey that saves the output
--	make hotkeys that jump between commands, possibly with a number in front e.g. :3hj, :3hk
