AddCSLuaFile()

module( "wt_iocommon", package.seeall )

CLASS_BASE = 1
CLASS_POINT = 2
CLASS_SOLID = 4
CLASS_KEYFRAME = 8
CLASS_MOVE = 16
CLASS_NPC = 32
CLASS_FILTER = 64
CLASS_NODE = 128

local classes = {
	["baseclass"] = CLASS_BASE,
	["pointclass"] = CLASS_POINT,
	["solidclass"] = CLASS_SOLID,
	["keyframeclass"] = CLASS_KEYFRAME,
	["moveclass"] = CLASS_MOVE,
	["npcclass"] = CLASS_NPC,
	["filterclass"] = CLASS_FILTER,
}

local meta_var = {}
meta_var.__index = meta_var

local meta_class = {}
meta_class.__index = meta_class

local meta_gamedata = {}
meta_gamedata.__index = meta_gamedata

function meta_var:Parse(stream)
	local t,s = stream:Token(wt_lexer.TOK_IDENT)
	if not t then return false end
	self.name = s
	if not stream:Token(wt_lexer.TOK_OP, '(') then return false end
	t,s = stream:Token()
	if t == wt_lexer.TOK_OP then
		if s == '*' then self.reportable = true end
	else
		stream:Store(t,s)
	end

	t,s = stream:Token(wt_lexer.TOK_IDENT)
	if not t then return false end
	if not stream:Token(wt_lexer.TOK_OP, ')') then return false end

	self.type = s

	t,s = stream:TokPeek()
	if t == wt_lexer.TOK_IDENT and s == "readonly" then
		t,s = stream:Token()
		self.readonly = true
		t,s = stream:TokPeek()
	end

	if t == wt_lexer.TOK_OP and s == ':' then
		t,s = stream:Token()
		if self.type == "flags" then return false end

		t,s = stream:Token()
		self.longname = s
		t,s = stream:TokPeek()
		if t == wt_lexer.TOK_OP and s == ':' then
			t,s = stream:Token()
			t,s = stream:TokPeek()
			if t == wt_lexer.TOK_OP and s == ':' then
			else
				t,s = stream:Token()
				self.default = s
				t,s = stream:TokPeek()
			end
		end

		if t == wt_lexer.TOK_OP and s == ':' then
			t,s = stream:Token()
			t,s = stream:Token()
			self.desc = s
			t,s = stream:TokPeek()
		end
	else
		self.longname = self.name
	end

	if (t == wt_lexer.TOK_OP and s == ']') or t ~= wt_lexer.TOK_OP then
		if self.type == "flags" or self.type == "choices" then return false end
		return true
	end

	if not stream:Token(wt_lexer.TOK_OP, '=') then return false end
	if self.type ~= "flags" and self.type ~= "choices" then return false end
	if not stream:Token(wt_lexer.TOK_OP, '[') then return false end

	if self.type == "flags" then

		self.choices = {}
		while true do
			local choice = {}
			t,s = stream:TokPeek()
			if t ~= wt_lexer.TOK_INT then break end
			t,s = stream:Token()
			choice.value = tonumber(s)
			if not stream:Token(wt_lexer.TOK_OP, ':') then return false end
			choice.caption = stream:TokStr()
			if not stream:Token(wt_lexer.TOK_OP, ':') then return false end
			choice.default = stream:TokInt()
			self.choices[#self.choices+1] = choice
		end

	elseif self.type == "choices" then

		self.choices = {}
		while true do
			local choice = {}
			t,s = stream:TokPeek()
			if t ~= wt_lexer.TOK_INT and t ~= wt_lexer.TOK_STRING then break end
			t,s = stream:Token()
			choice.value = s
			if not stream:Token(wt_lexer.TOK_OP, ':') then return false end
			choice.caption = stream:TokStr()
			self.choices[#self.choices+1] = choice
		end

	end

	if not stream:Token(wt_lexer.TOK_OP, ']') then return false end

	return true

end

function FGDVar()
	return setmetatable({}, meta_var)
end

function meta_class:GetNumBaseClasses()
    return #self.bases
end

function meta_class:GetBaseClass(i)
    if i > #self.bases then return end
    return self.parent.classes[self.bases[i]]
end

function meta_class:AddBase(base, idx)
    for _,v in ipairs(base.inputs) do
        local copy = table.Copy(v)
        copy.classid = idx
        self.inputs[#self.inputs+1] = copy
    end
    for _,v in ipairs(base.outputs) do
        local copy = table.Copy(v)
        copy.classid = idx
        self.outputs[#self.outputs+1] = copy
    end
    for k,v in ipairs(base.vars) do
        local copy = table.Copy(v)
        copy.classid = idx
        self:AddVariable( copy, base, idx, k )
    end
    self.color = self.color or base.color
    self.bases[#self.bases+1] = idx
end

function meta_class:ParseBase(stream)
	while stream:TokPeek() == wt_lexer.TOK_IDENT do
		local t,s = stream:Token()
        local base, idx = self.parent:FindClass(s)
        if base == nil then print("Undefined base class: " .. tostring(s)) return false end
        self:AddBase(base, idx)
		t,s = stream:Token(wt_lexer.TOK_OP)
		if not t then return false end
		if s == ')' then break end
		if s ~= ',' then return false end
	end
	return true
end

function meta_class:ParseSize(stream)
	for i=1, 3 do
		local k = stream:TokInt()
		if not k then return false end
		self.mins[i] = k
	end
	local t,s = stream:TokPeek()
	if t == wt_lexer.TOK_OP and s == ',' then
		stream:Token()
		for i=1, 3 do
			local k = stream:TokInt()
			if not k then return false end
			self.maxs[i] = k
		end
	else
		for i=1, 3 do
			local d = self.mins[i] / 2
			self.maxs[i] = d
			self.mins[i] = -d
		end
	end
	if not stream:Token(wt_lexer.TOK_OP, ')') then return false end
	return true
end

function meta_class:ParseColor(stream)
	local r, g, b = stream:TokInt(), stream:TokInt(), stream:TokInt()
	if not r or not g or not b then return false end
	if not stream:Token(wt_lexer.TOK_OP, ')') then return false end
	self.color = Color(r,g,b)
	return true
end

function meta_class:ParseHelper(stream, name)
	local helper = {}
	local params = {}
	helper.name = name
	helper.params = params

	local close = false
	while not close do
		if stream:TokPeek() == wt_lexer.TOK_OP then
			local t,s = stream:Token()
			if s == ')' then
				close = true
			elseif s == '=' then
				return false
			end
		else
			local t,s = stream:Token()
			params[#params+1] = s
		end
	end
	self.helpers[#self.helpers+1] = helper
    self.helper_lookup[helper.name] = params
	return true
end

function meta_class:ParseSpec(stream)
	while stream:TokPeek() == wt_lexer.TOK_IDENT do
		local t,s = stream:Token()
		if s == "halfgridsnap" then continue end
		if not stream:Token(wt_lexer.TOK_OP, '(') then return false end

		if s == "base" then if not self:ParseBase(stream) then return false end
		elseif s == "size" then if not self:ParseSize(stream) then return false end
		elseif s == "color" then if not self:ParseColor(stream) then return false end
		elseif not self:ParseHelper(stream, s) then return false end
	end
	return true
end

function meta_class:ParseInputOutput(stream)
	local io = {}
    io.classid = -1
	io.name = stream:TokStr(wt_lexer.TOK_IDENT)
	if not stream:Token(wt_lexer.TOK_OP, '(') then return nil end
	io.type = stream:TokStr(wt_lexer.TOK_IDENT)
	if not stream:Token(wt_lexer.TOK_OP, ')') then return nil end
	local t,s = stream:TokPeek()
	if t == wt_lexer.TOK_OP and s == ':' then
		t,s = stream:Token()
		io.desc = stream:TokStr(wt_lexer.TOK_STRING)
	end
	return io
end

function meta_class:ParseInput(stream)
	if not stream:Token(wt_lexer.TOK_IDENT, "input") then return false end
	local io = self:ParseInputOutput(stream)
	if io == nil then return false end
	self.inputs[#self.inputs+1] = io
	return true
end

function meta_class:ParseOutput(stream)
	if not stream:Token(wt_lexer.TOK_IDENT, "output") then return false end
	local io = self:ParseInputOutput(stream)
	if io == nil then return false end
	self.outputs[#self.outputs+1] = io
	return true
end

function meta_class:ParseVariables(stream)
	while not stream.eof do
		local t,s = stream:TokPeek()
		if t == wt_lexer.TOK_OP then break end
		if s == "input" then if not self:ParseInput(stream) then return false end continue end
		if s == "output" then if not self:ParseOutput(stream) then return false end continue end
		if s == "key" then t,s = stream:Token() end
		local var = FGDVar()
		if not var:Parse(stream) then return false end
		self:AddVariable(var, self, -1, #self.vars)
	end
	return true
end

function meta_class:Parse(stream)
	if not self:ParseSpec(stream) then return false end
	if not stream:Token(wt_lexer.TOK_OP, '=') then return false end
	self.name = stream:TokStr()
	if not self.name then return false end
	local t,s = stream:TokPeek()
	if t == wt_lexer.TOK_OP and s == ':' then
		t,s = stream:Token()
		self.desc = stream:TokStr()
	end
	if not stream:Token(wt_lexer.TOK_OP, '[') then return false end
	if not self:ParseVariables(stream) then print("FAILED TO PARSE VARS") return false end
	if not stream:Token(wt_lexer.TOK_OP, ']') then return false end
	return true
end

function meta_class:AddVariable(var, base, baseidx, varidx)
    var.classid = var.classid or -1
    local exist, existidx = self:FindVar(var.name)
    if exist then
        -- TODO: Merge choices / flags
        self.vars[existidx] = var
    else
        self.vars[#self.vars+1] = var
    end
end

function meta_class:FindVar(name)
    for k,v in ipairs(self.vars) do
        if v.name == name then return v,k end
    end
end

local function FGDClass(class_type)
	return setmetatable({ 
		type = class_type, 
		bases = {},
		mins = {0,0,0},
		maxs = {0,0,0},
        helper_lookup = {},
		helpers = {},
		inputs = {},
		outputs = {},
		vars = {},
	}, meta_class)
end

function meta_gamedata:FindClass(name)

    for k,v in ipairs(self.classes) do
        if v.name == name then return v,k end
    end

end

function meta_gamedata:ParseFGDString(text)

    local start = SysTime()
    local stream = wt_lexer.New(text)
    while not stream.eof do
        local t,s = stream:Token()
        if t == wt_lexer.TOK_EOF then break end
        if t ~= wt_lexer.TOK_OP or s ~= '@' then
            print("Expected @")
            return false
        end

        t,s = stream:Token()
        if t ~= wt_lexer.TOK_IDENT then
            print("Expected identifier after @")
            return false
        end

        local class_type = classes[s]
        if class_type then
            local cl = FGDClass(class_type)
            cl.parent = self
            if class_type > CLASS_SOLID then class_type = bit.bor(class_type, CLASS_POINT) end
            if not cl:Parse(stream) then
                print("Failed to parse class on line: " .. stream.line)
                stream:SkipTo(wt_lexer.TOK_OP, '@')
            end
            local exist, idx = self:FindClass(cl.name)
            if exist ~= nil then
                self.classes[idx] = cl
                cl.classid = idx
            else
                self.classes[#self.classes+1] = cl
                cl.classid = #self.classes
            end
        else
            print("Unknown section '" .. tostring(s) .. "' skipping...")
            stream:SkipTo(wt_lexer.TOK_OP, '@')
        end
    end

    print("Parse took " .. (SysTime() - start) * 1000 .. "ms")

end

--[[function FGDGameData()
    return setmetatable({
        classes = {},
    }, meta_gamedata)
end

local GameData = FGDGameData()

local function parseFGD( fgd, path )

	local f = file.Open( fgd, "rb", path or "BASE_PATH" )
	if f then
		str = f:Read( f:Size() )
        GameData:ParseFGDString(str)
	else
		print("FGD file not found: " .. tostring(fgd))
	end

end

if CLIENT then

    parseFGD("bin/base.fgd")
    parseFGD("bin/halflife2.fgd")
    parseFGD("bin/garrysmod.fgd")

    local classdata = GameData:FindClass("trigger_catapult")
    local k = classdata.parent
    classdata.parent = nil
    PrintTable( classdata )
    classdata.parent = k

end]]