local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local util = import("micro/util")
local strings = import("strings")
local filepath = import("filepath")
local os_ = import("os")
local regexp = import("regexp")

local jumpStack = {}

function jumpPush(bp, s)
    local id = bp:ID()
    if jumpStack[id] == nil then
        jumpStack[id] = {}
    end
    table.insert(jumpStack[id], s)
end

function jumpPop(bp)
    local id = bp:ID()
    if jumpStack[id] == nil then
        return
    end

    local s = table.remove(jumpStack[id])
    if #jumpStack[id] == 0 then
        jumpStack[id] = nil
    end
    return s
end

function canJump(bp, path, loc)
    if bp.Buf.Type.Kind ~= buffer.BTDefault then
        micro.InfoBar():Error("Jumping not supported for non-file buffers")
        return false
    end

    if filepath.Abs(path) ~= bp.Buf.AbsPath then
        if bp.Buf:Modified() then
            micro.InfoBar():Error("Save changes before jumping to ", path)
            return false
        end

        local buf, err = buffer.NewBufferFromFile(path)
        if err ~= nil then
            micro.InfoBar():Error(err)
            return false
        end
        return true, buf
    end

    return true, bp.Buf
end

function doJump(bp, buf, loc, push)
    if push and bp.Buf.Path ~= "" and (bp.Buf ~= buf or loc.Y ~= bp.Cursor.Loc.Y) then
        local s = {
            path = bp.Buf.AbsPath,
            loc = -bp.Cursor.Loc,
            sel = -bp.Cursor.CurSelection,
            osel = -bp.Cursor.OrigSelection,
            view = -bp:GetView(),
            bview = bp:BufView(),
        }
        jumpPush(bp, s)
    end

    if bp.Buf ~= buf then
        buf:GetActiveCursor():GotoLoc(loc)
        bp:OpenBuffer(buf)
    else
        bp:GotoLoc(loc)
    end
    bp:ClearInfo()
    return true
end

function jump(bp, path, loc, push)
    local ok, buf = canJump(bp, path, loc)
    if ok then
        doJump(bp, buf, loc, push)
        return true
    end
    return false
end

function jumpBack(bp)
    local s = jumpPop(bp)
    if s == nil then
        return false
    end

    local path = s.path
    local rel, err = filepath.Rel(os_.Getwd(), path)
    if err == nil then
        path = rel
    end

    if not jump(bp, path, s.loc, false) then
        jumpPush(bp, s)
        return false
    end

    bp.Cursor.CurSelection = s.sel
    bp.Cursor.OrigSelection = s.osel

    local v = bp:GetView()
    local bv = bp:BufView()
    if bv.Height == s.bview.Height then
        v.StartLine = s.view.StartLine
    end
    if bv.Width == s.bview.Width then
        v.StartCol = s.view.StartCol
    end

    return true
end

function selectAtCurLine(bp, regex, loc)
    local loc = -bp.Cursor.Loc
    local eol = buffer.Loc(util.CharacterCountInString(bp.Buf:Line(loc.Y)), loc.Y)
    local floc, found = bp.Buf:FindNext(regex, loc, eol, loc, true, true)
    if found then
        bp.Cursor:SetSelectionStart(floc[1])
        bp.Cursor:SetSelectionEnd(floc[2])
        bp.Cursor.OrigSelection = -bp.Cursor.CurSelection
        bp.Cursor:GotoLoc(floc[2])
        bp:Relocate()
    end
end

function parse(str)
    local split = strings.SplitN(str, ":", 3)
    if #split < 3 then
        return false
    end
    local line = tonumber(split[2])
    if line == fail or line <= 0 then
        return false
    end
    return true, split[1], line - 1, split[3]
end

function isMultiline(output)
    local m = string.find(output, "\n")
    return m ~= fail and m < string.len(output)
end

local grepProg = "grep -rnPI --exclude-dir=.git --color=always"
local tagProg = "global --result=grep"
local fzfProg = "fzf --layout=reverse --ansi"

function grep(bp, args)
    if #args < 1 then
        return
    end

    local output, err = shell.RunInteractiveShell("sh -c '" .. grepProg .. " " ..
            strings.Join(args, " ") .. " | " .. fzfProg .. "'", false, true)
    if err ~= nil then
        return
    end
    if output == "" then
        micro.InfoBar():Message("No matches found")
        return
    end

    local ok, path, line, _ = parse(output)
    if not ok then
        micro.InfoBar():Error("Invalid grep output: ", output)
        return
    end

    local loc = buffer.Loc(0, line)
    if jump(bp, path, loc, true) then
        local pattern = args[#args]     -- TODO: other cases
        selectAtCurLine(bp, pattern)
    end
end

function tagPatternRegex(pattern)
    if regexp.QuoteMeta(pattern) == pattern then
        return "\\b" .. pattern .. "\\b"
    end
    return pattern
end

function tagFullpatternRegex(pattern)
    local regex = regexp.QuoteMeta(pattern)
    regex = regex:gsub("%s+", "\\s+")   -- gtags merges spaces
    regex = "^\\s*" .. regex .. "\\s*$"
    return regex
end

function tag(bp, args)
    if #args < 1 then
        return
    end
    local pattern = args[1]

    local output, err = shell.RunCommand(tagProg .. " " .. pattern)
    if err ~= nil then
        micro.InfoBar():Error(output)
        return
    end
    if isMultiline(output) then
        output, err = shell.RunInteractiveShell("sh -c '" .. tagProg ..
                " --color=always " .. pattern .. " | " .. fzfProg .. "'", false, true)
        if err ~= nil then
            return
        end
    end
    output = strings.TrimRight(output, "\r\n")
    if output == "" then
        micro.InfoBar():Message("No tag found for ", pattern)
        return
    end

    local ok, path, line, fullpattern = parse(output)
    if not ok then
        micro.InfoBar():Error("Invalid tag output: ", output)
        return
    end

    local loc = buffer.Loc(0, line)
    local ok, buf = canJump(bp, path, loc)
    if ok then
        local bStart = buf:Start()
        local bEnd = buf:End()

        -- try to find a precise match
        local regex = tagFullpatternRegex(fullpattern)
        local floc, found = buf:FindNext(regex, bStart, bEnd, loc, true, true)
        if found then
            doJump(bp, buf, floc[1], true)
            selectAtCurLine(bp, tagPatternRegex(pattern))
            if floc[1].Y ~= loc.Y then
                micro.InfoBar():Message("Found tag for ", pattern, " with offset ",
                                        floc[1].Y - loc.Y)
            end
        else
            -- try to guess an imprecise match
            regex = tagPatternRegex(pattern)
            floc, found = buf:FindNext(regex, bStart, bEnd, loc, true, true)
            if found then
                local nloc = floc[1]

                -- try also searching backwards, maybe there is a closer match
                floc, found = buf:FindNext(regex, bStart, bEnd, loc, false, true)
                if found and math.abs(loc.Y - floc[1].Y) < math.abs(loc.Y - nloc.Y) then
                    nloc = floc[1]
                end

                doJump(bp, buf, nloc, true)
                selectAtCurLine(bp, regex)
                micro.InfoBar():Message("Guessed tag for ", pattern,
                                        ". Try regenerating GTAGS.")
            else
                micro.InfoBar():Message("No tag found for ", pattern, " in ", path,
                                        ". Try regenerating GTAGS.")
            end
        end
    end
end

function doClick(bp, e, func)
    local mx, my = e:Position()
    if my >= bp:BufView().Y + bp:BufView().Height then
        return
    end
    local loc = bp:LocFromVisual(buffer.Loc(mx, my))

    if util.IsWordChar(util.RuneAt(bp.Buf:LineBytes(loc.Y), loc.X)) then
        bp.Cursor.Loc = loc
        bp.Cursor:SelectWord()
        func(bp)
    else
        jumpBack(bp)
    end
end

function grepClick(bp, e)
    doClick(bp, e, function(bp)
        grep(bp, {"-w", util.String(bp.Cursor:GetSelection())})
    end)
end

function tagClick(bp, e)
    doClick(bp, e, function(bp)
        tag(bp, {util.String(bp.Cursor:GetSelection())})
    end)
end

function init()
    config.MakeCommand("tag", tag, config.NoComplete)
    config.MakeCommand("grep", grep, config.NoComplete)

    config.TryBindKey("Ctrl-MouseRight", "lua:nav.tagClick", false)
    config.TryBindKey("Alt-MouseRight", "lua:nav.grepClick", false)

    config.TryBindKey("F9", "lua:nav.jumpBack", false)
end
