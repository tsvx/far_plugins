-- utils.lua --

local P = {} -- "package"
local F = far.Flags
local band, bor, bxor, bnot = bit64.band, bit64.bor, bit64.bxor, bit64.bnot
local PluginDir = far.PluginStartupInfo().ModuleName:match(".*\\")

function P.CheckLuafarVersion (reqVersion, msgTitle)
  local v1, v2 = far.LuafarVersion(true)
  local r1, r2 = reqVersion[1], reqVersion[2]
  if (v1 > r1) or (v1 == r1 and v2 >= r2) then return true end
  far.Message(
    ("LuaFAR %s or newer is required\n(loaded version is %s)")
    :format(reqVersion, far.LuafarVersion()),
    msgTitle, ";Ok", "w")
  return false
end

local function OnError (msg)
  local Lower = far.LLowerBuf

  local tPaths = { Lower(PluginDir) }
  for dir in package.path:gmatch("[^;]+") do
    tPaths[#tPaths+1] = Lower(dir):gsub("/", "\\"):gsub("[^\\]+$", "")
  end

  local function repair(str)
    local Lstr = Lower(str):gsub("/", "\\")
    for _, dir in ipairs(tPaths) do
      local part1, part2 = Lstr, ""
      while true do
        local p1, p2 = part1:match("(.*[\\/])(.+)")
        if not p1 then break end
        part1, part2 = p1, p2..part2
        if part1 == dir:sub(-part1:len()) then
          return dir .. str:sub(-part2:len())
        end
      end
    end
  end

  local jumps, buttons = {}, "&OK"
  msg = tostring(msg):gsub("[^\n]+",
    function(line)
      line = line:gsub("^\t", ""):gsub("(.-)%:(%d+)%:(%s*)",
        function(file, numline, space)
          if #jumps < 10 then
            local file2 = file:sub(1,3) ~= "..." and file or repair(file:sub(4))
            if file2 then
              local name = file2:match('^%[string "(.*)"%]$')
              if not name or name=="all text" or name=="selection" then
                jumps[#jumps+1] = { file=file2, line=tonumber(numline) }
                buttons = buttons .. ";&" .. (#jumps)
                return ("\16[J%d]:%s:%s:%s"):format(#jumps, file, numline, space)
              end
            end
          end
          return "[?]:" .. file .. ":" .. numline .. ":" .. space
        end)
      return line
    end)
  collectgarbage "collect"
  local caption = ("Error [used: %d Kb]"):format(collectgarbage "count")
  local ret = far.Message(msg, caption, buttons, "wl")
  if ret <= 0 then return end

  local file, line = jumps[ret].file, jumps[ret].line
  local luaScript = file=='[string "all text"]' or file=='[string "selection"]'
  if not luaScript then
    local trgInfo
    for i=1,far.AdvControl("ACTL_GETWINDOWCOUNT") do
      local wInfo = far.AdvControl("ACTL_GETWINDOWINFO", i-1)
      if wInfo.Type==F.WTYPE_EDITOR and
        Lower(wInfo.Name:gsub("/","\\")) == Lower(file:gsub("/","\\"))
      then
        trgInfo = wInfo
        if wInfo.Current then break end
      end
    end
    if trgInfo then
      if not trgInfo.Current then
        far.AdvControl("ACTL_SETCURRENTWINDOW", trgInfo.Pos)
        far.AdvControl("ACTL_COMMIT")
      end
    else
      far.Editor(file, nil,nil,nil,nil,nil, {EF_NONMODAL=1,EF_IMMEDIATERETURN=1})
    end
  end

  local eInfo = far.EditorGetInfo()
  if eInfo then
    if file == '[string "selection"]' then
      local startsel = eInfo.BlockType~=F.BTYPE_NONE and eInfo.BlockStartLine or 0
      line = line + startsel
    end
    local offs = math.floor(eInfo.WindowSizeY / 2)
    far.EditorSetPosition(nil, line-1, 0, 0, line>offs and line-offs or 0)
    far.EditorRedraw()
  end
end

function P.RunScript (name, ...)
  local embed_name = "<"..name
  if package.preload[embed_name] then -- prevent unnecessary disk search with non-embed plugin
    return require(embed_name)(...)
  end
  local func, errmsg = loadfile(PluginDir..name..".lua")
  if func then return func(...) end
  error(errmsg)
end

-- @aItem.filename:  script file name
-- @aItem.env:       environment to run the script in
-- @aItem.arg:       array of arguments associated with aItem
--
-- @aProperties:     table with property-like arguments, e.g.: "From", "hDlg"
--
-- ...:              sequence of additional arguments (appended to existing arguments)
--
function P.RunUserFunc (aItem, aProperties, ...)
  assert(aItem.filename, "no file name")
  assert(aItem.env, "no environment")
  -- compile the file
  local chunk, msg = loadfile(aItem.filename)
  if not chunk then error(msg,2) end
  -- copy "fixed" and append "variable" arguments
  local args = {}
  for k,v in pairs(aProperties) do args[k] = v end
  for i,v in ipairs(aItem.arg)  do args[i] = v end
  for i=1,select("#", ...) do args[#args+1] = select(i, ...) end
  -- run the chunk
  setfenv(chunk, aItem.env)
  chunk(args)
end

local function ConvertUserHotkey(str)
  local d = 0
  for elem in str:upper():gmatch("[^+-]+") do
    if elem == "ALT" then d = bor(d, 0x01)
    elseif elem == "CTRL" then d = bor(d, 0x02)
    elseif elem == "SHIFT" then d = bor(d, 0x04)
    else d = d .. "+" .. elem; break
    end
  end
  return d
end

local function MakeAddToMenu (Items, Env, HotKeyTable)
  local function AddToMenu (aWhere, aItemText, aHotKey, aFileName, ...)
    if type(aWhere) ~= "string" then return end
    aWhere = aWhere:lower()
    if not aWhere:find("[evpdc]") then return end
    ---------------------------------------------------------------------------
    local SepText = type(aItemText)=="string" and aItemText:match("^:sep:(.*)")
    local bUserItem = SepText or type(aFileName)=="string"
    if not bUserItem then
      if aItemText~=true or type(aFileName)~="number" then
        return
      end
    end
    ---------------------------------------------------------------------------
    if HotKeyTable and not SepText and aWhere:find("[ec]") and type(aHotKey)=="string" then
      aHotKey = ConvertUserHotkey (aHotKey)
      if bUserItem then
        HotKeyTable[aHotKey] = {filename=PluginDir..aFileName, env=Env, arg={...}}
      else
        HotKeyTable[aHotKey] = aFileName
      end
    end
    ---------------------------------------------------------------------------
    if bUserItem and aItemText then
      local item
      if SepText then
        item = { text=SepText, separator=true }
      else
        item = { text=tostring(aItemText),
                 filename=PluginDir..aFileName, env=Env, arg={...} }
      end
      if aWhere:find"c" then table.insert(Items.config, item) end
      if aWhere:find"d" then table.insert(Items.dialog, item) end
      if aWhere:find"e" then table.insert(Items.editor, item) end
      if aWhere:find"p" then table.insert(Items.panels, item) end
      if aWhere:find"v" then table.insert(Items.viewer, item) end
    end
  end
  return AddToMenu
end

local function MakeAddCommand (CommandTable, Env)
  return function (aCommand, aFileName, ...)
    if type(aCommand)=="string" and type(aFileName)=="string" then
      CommandTable[aCommand] = { filename=PluginDir..aFileName, env=Env, arg={...} }
    end
  end
end

local function MakeAutoInstall (AddUserFile)
  local function AutoInstall (startpath, filepattern, depth)
    assert(type(startpath)=="string", "bad arg. #1 to AutoInstall")
    assert(filepattern==nil or type(filepattern)=="string", "bad arg. #2 to AutoInstall")
    assert(depth==nil or type(depth)=="number", "bad arg. #3 to AutoInstall")
    ---------------------------------------------------------------------------
    startpath = PluginDir .. startpath:gsub("[\\/]*$", "\\", 1)
    filepattern = filepattern or "^_usermenu%.lua$"
    ---------------------------------------------------------------------------
    local first = depth
    local offset = PluginDir:len() + 1
    for _, item in ipairs(far.GetDirList(startpath) or {}) do
      if first then
        first = false
        local _, m = item.FileName:gsub("\\", "")
        depth = depth + m
      end
      if not item.FileAttributes:find"d" then
        local try = true
        if depth then
          local _, n = item.FileName:gsub("\\", "")
          try = (n <= depth)
        end
        if try then
          local relName = item.FileName:sub(offset)
          local Name = relName:match("[^\\/]+$")
          if Name:match(filepattern) then AddUserFile(relName) end
        end
      end
    end
  end
  return AutoInstall
end

function P.LoadUserMenu (aFileName, aMakeResident)
  local userItems = { editor={},viewer={},panels={},config={},cmdline={},dialog={} }
  local commandTable, hotKeyTable = {}, {}
  local uStack, uDepth, uMeta = {}, 0, {__index = _G}
  local env = setmetatable({}, {__index=_G})

  env.AddUserFile = function (filename)
    uDepth = uDepth + 1
    filename = PluginDir .. filename
    if uDepth == 1 then
      -- if top-level _usermenu.lua doesn't exist, it isn't error
      local attr = win.GetFileAttr(filename)
      if not attr or attr:find("d") then return end
    end
    ---------------------------------------------------------------------------
    local chunk = assert(loadfile(filename))
    ---------------------------------------------------------------------------
    uStack[uDepth] = setmetatable({}, uMeta)
    env.AddToMenu = MakeAddToMenu(userItems, uStack[uDepth], hotKeyTable)
    env.AddCommand = MakeAddCommand(commandTable, uStack[uDepth])
    setfenv(chunk, env)()
    uDepth = uDepth - 1
  end

  env.AutoInstall = MakeAutoInstall(env.AddUserFile)
  env.MakeResident = aMakeResident

  env.AddUserFile(aFileName)
  return userItems, commandTable, hotKeyTable
end

function P.AddMenuItems (src, trg, msgtable)
  trg = trg or {}
  for _, item in ipairs(src) do
    local text = item.text
    if type(text)=="string" and text:sub(1,2)=="::" then
      local newitem = {}
      for k,v in pairs(item) do newitem[k] = v end
      newitem.text = msgtable[text:sub(3)]
      trg[#trg+1] = newitem
    else
      trg[#trg+1] = item
    end
  end
  return trg
end

local function CommandSyntaxMessage (tCommands)
  local globalInfo = export.GetGlobalInfo()
  local pluginInfo = export.GetPluginInfo()
  local syn = [[

Command line syntax:
  %s: [<options>] <command>|-r<filename> [<arguments>]

Macro call syntax:
  CallPlugin("%s",
      "[<options>] <command>|-r<filename> [<arguments>]")

Options:
  -a          asynchronous execution
  -e <str>    execute string <str>
  -l <lib>    load library <lib>

Available commands:
]]

  syn = syn:format(pluginInfo.CommandPrefix, win.Uuid(globalInfo.Guid))
  if next(tCommands) then
    local arr = {}
    for k in pairs(tCommands) do arr[#arr+1] = k end
    table.sort(arr)
    syn = syn .. "  " .. table.concat(arr, ", ")
  else
    syn = syn .. "  <no commands available>"
  end
  far.Message(syn, globalInfo.Title, ";Ok", "l")
end

-- Split command line into separate arguments.
-- * An argument is either of:
--     a) a sequence of 0 or more characters enclosed within a pair of non-escaped
--        double quotes; can contain spaces; enclosing double quotes are stripped
--        from the argument.
--     b) a sequence of 1 or more non-space characters.
-- * Backslashes only escape double quotes.
-- * The function does not raise errors.
local function SplitCommandLine (str)
  local pat = [["((?:\\"|[^"])*)"|((?:\\"|\S)+)]]
  local out = {}
  for c1, c2 in far.gmatch(str, pat) do
    out[#out+1] = far.gsub(c1 or c2, [[\\(")|(.)]], "%1%2")
  end
  return out
end

local function CompileCommandLine (sCommandLine, tCommands)
  local actions = {}
  local opt
  local args = SplitCommandLine(sCommandLine)
  for i,v in ipairs(args) do
    local curropt, param
    if opt then
      curropt, param, opt = opt, v, nil
    else
      if v:sub(1,1) == "-" then
        local newopt
        newopt, param = v:match("^%-([aelr])(.*)")
        if newopt == nil then
          error("invalid option: "..v)
        end
        if newopt == "a" then actions.async = true
        elseif param == "" then  opt = newopt
        else curropt = newopt
        end
      else
        if not tCommands[v] then
          error("invalid command: "..v)
        end
        actions[#actions+1] = { command=v, unpack(args, i+1) }
        break
      end
    end
    if curropt == "r" then
      actions[#actions+1] = { opt=curropt, param=param, unpack(args, i+1) }
      break
    elseif curropt then
      actions[#actions+1] = { opt=curropt, param=param }
    end
  end
  return actions
end

local function ExecuteCommandLine (tActions, tCommands, sFrom, fConfig)
  local function wrapfunc()
    local env = setmetatable({}, {__index=_G})
    for i,v in ipairs(tActions) do
      if v.command then
        local fileobject = tCommands[v.command]
        P.RunUserFunc(fileobject, {From=sFrom}, unpack(v))
        break
      elseif v.opt == "r" then
        local path = v.param
        if not path:find("^[a-zA-Z]:") then
          local panelDir = far.CtrlGetPanelDir(nil, 1)
          if path:find("^[\\/]") then
            path = panelDir:sub(1,2) .. path
          else
            path = panelDir:gsub("[^\\/]$", "%1\\") .. path
          end
        end
        local f = assert(loadfile(path))
        setfenv(f, env)(unpack(v))
      elseif v.opt == "e" then
        local f = assert(loadstring(v.param))
        setfenv(f, env)()
      elseif v.opt == "l" then
        require(v.param)
      end
    end
  end
  local oldConfig = fConfig and fConfig()
  local ok, res = xpcall(wrapfunc, function(msg) return debug.traceback(msg, 3) end)
  if fConfig then fConfig(oldConfig) end
  if not ok then P.ScriptErrMsg(res) end
end

-- This function processes both command line calls and calls from macros.
local function ProcessCommandLine (sCommandLine, tCommands, sFrom, fConfig)
  local tActions = CompileCommandLine(sCommandLine, tCommands)
  if not tActions[1] then
    CommandSyntaxMessage(tCommands)
  elseif tActions.async then
    ---- autocomplete:good; Escape response:bad when timer period < 20;
    far.Timer(30,
      function(h)
        if not h.Closed then
          h:Close(); ExecuteCommandLine(tActions, tCommands, sFrom, fConfig)
        end
      end)
  else
    ---- autocomplete:bad; Escape responsiveness:good;
    ExecuteCommandLine(tActions, tCommands, sFrom, fConfig)
  end
end

function P.OpenMacroOrCommandLine (aFrom, aItem, aCommandTable, fConfig)
  if band(aFrom, bnot(F.OPEN_FROM_MASK)) ~= 0 then
    -- called from macro
    if band(aFrom, F.OPEN_FROMMACRO) ~= 0 then
      aFrom = band(aFrom, bnot(F.OPEN_FROMMACRO))
      if band(aFrom, F.OPEN_FROMMACRO_MASK) == F.OPEN_FROMMACROSTRING then
        local map = {
          [F.MACROAREA_SHELL]  = "panels",
          [F.MACROAREA_EDITOR] = "editor",
          [F.MACROAREA_VIEWER] = "viewer",
          [F.MACROAREA_DIALOG] = "dialog",
        }
        local lowByte = band(aFrom, F.OPEN_FROM_MASK)
        ProcessCommandLine(aItem, aCommandTable, map[lowByte] or aFrom, fConfig)
      end
    end
    return true
  elseif aFrom == F.OPEN_COMMANDLINE then
    -- called from command line
    ProcessCommandLine(aItem, aCommandTable, "panels", fConfig)
    return true
  end
  return false
end

-- Add function unicode.utf8.cfind:
-- same as find, but offsets are in characters rather than bytes
-- DON'T REMOVE: it's documented in LF4Ed manual and must be available to user scripts.
local function AddCfindFunction()
  local usub, ssub = unicode.utf8.sub, string.sub
  local ulen, slen = unicode.utf8.len, string.len
  local ufind = unicode.utf8.find
  unicode.utf8.cfind = function(s, patt, init, plain)
    init = init and slen(usub(s, 1, init-1)) + 1
    local t = { ufind(s, patt, init, plain) }
    if t[1] == nil then return nil end
    return ulen(ssub(s, 1, t[1]-1)) + 1, ulen(ssub(s, 1, t[2])), unpack(t, 3)
  end
end

function P.InitPlugin()
  getmetatable("").__index = unicode.utf8
  AddCfindFunction()

  export.OnError = OnError

  local plugin = {}
  plugin.ModuleDir = PluginDir
  return plugin
end

return P
