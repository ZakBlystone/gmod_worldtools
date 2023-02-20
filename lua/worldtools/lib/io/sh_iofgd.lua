AddCSLuaFile()

module( "wt_iocommon", package.seeall )

FGDClasses = {}

local function lines(str, newline)
	local setinel = 0
	local newlen = string.len(newline or "\r\n")
	return function()
		local k = str:find(newline or "\r\n", setinel+1)
		if not k then return end
		local b = setinel
		setinel = k
		return str:sub(b+newlen, k-1)
	end
end

local classes = {}
local classMatch = "^@(%w+)(.*)=%s-([%w_]+)"
local classNameMatch = "=%s-([%w_]+)"
local outputMatch = "^%s*output%s(%w+)%((%w+)%)"
local inputMatch = "^%s*input%s(%w+)%((%w+)%)"
local argListMatch = "(%w+%([^%)]*%))"
local argKVMatch = "(%w+)%(([^%)]*)%)"
local argMultiMatch = "[^,%s]+"
local kvMatchFull = [[(%w+)%((%w+)%)%s*:%s*"([^"]*)"%s*:%s*"([^"]*)"]]
local kvMatchPartial = [[(%w+)%((%w+)%)%s*:%s*"([^"]*)"]]

local function tablesEqual(a,b)

	for k,v in pairs(b) do
		if not a[k] then return false end
	end

	for k,v in pairs(a) do
		if not b[k] then return false end
		if type(v) ~= type(b[k]) then return false end
		if type(v) == "table" then
			if not tablesEqual(v, b[k]) then return false end
		end
	end
	return true

end

function parseFGDString( filename, str, newline )

	if str == nil then 
		print("FAILED TO LOAD: " .. tostring(filename))
		return
	else
		print("LOADING: " .. tostring(filename))
	end

	local targetClass = nil
	for x in lines( str, newline ) do

		if x:match("^%s*//") then continue end

		local classtype, args, name = x:match(classMatch)
		if classtype and name then
			if targetClass then 
				classes[targetClass.classname] = targetClass
			end
			targetClass = { 
				classname = name, 
				classtype = classtype,
				inputs = {},
				outputs = {},
				editorkeys = {},
				baseclasses = {},
				keyvalues = {},
			}

			if args then
				for arg in args:gmatch(argListMatch) do
					local k,v = arg:match(argKVMatch)
					if k == "base" then
						local bases = {}
						for base in v:gmatch(argMultiMatch) do
							bases[#bases+1] = base
						end
						targetClass.baseclasses = bases
					else
						if string.byte(v[1]) == nil then continue end
						local text = v:match("\"*([^\"]*)\"*")
						targetClass.editorkeys[k] = text
					end
				end
			end
		end

		if targetClass then
			if x[1] == ']' then
				if classes[targetClass.classname] then
					if tablesEqual(classes[targetClass.classname], targetClass) then
						--print("DUPLICATE CLASS: " .. targetClass.classname .. " from " .. filename)
					else
						--print("REDEFINED CLASS: " .. targetClass.classname .. " from " .. filename .. ", merging...")
						table.Merge(classes[targetClass.classname], targetClass)						
					end
				else
					classes[targetClass.classname] = targetClass
				end
				targetClass = nil
			else

				local output, param = x:match(outputMatch)
				if output then
					targetClass.outputs[output] = param
					continue
				end

				local input, param = x:match(inputMatch)
				if input then
					targetClass.inputs[input] = param
					continue
				end

				local key, type, desc, default = x:match(kvMatchFull)
				if key then
					targetClass.keyvalues[key] = {
						type = type, 
						desc = desc, 
						default = default
					}
					continue
				end

				local key, type, desc = x:match(kvMatchPartial)
				if key then
					targetClass.keyvalues[key] = {
						type = type, 
						desc = desc
					}
					continue
				end

			end
		end

	end

end

function parseFGD( fgd, path )

	local f = file.Open( fgd, "rb", path or "BASE_PATH" )
	if f then
		str = f:Read( f:Size() )
		parseFGDString(fgd, str)
	else
		print("FGD file not found: " .. tostring(fgd))
	end

end

local function walkAllBaseClasses(classes, class, bases)

	for _, base in ipairs(class.baseclasses) do

		local baseClass = classes[base]
		if not baseClass then 
			error("Failed to find class for: " .. base)
		end

		bases[#bases+1] = baseClass
		walkAllBaseClasses(classes, baseClass, bases)

	end

end

local function inheritBaseClasses(classes)

	for k, class in pairs(classes) do

		local bases = {}
		walkAllBaseClasses(classes, class, bases)

		for _, base in ipairs(bases) do

			for name, input in pairs(base.inputs) do
				if not class.inputs[name] then
					class.inputs[name] = input
				end
			end

			for name, output in pairs(base.outputs) do
				if not class.outputs[name] then
					class.outputs[name] = output
				end
			end

		end

	end

end

local start = SysTime()

parseFGD("bin/base.fgd")
parseFGD("bin/halflife2.fgd")
parseFGD("bin/garrysmod.fgd")

include("../fgd/sh_halflife_source.lua")
include("../fgd/sh_tf.lua")
include("../fgd/sh_left4dead2.lua")

inheritBaseClasses(classes)

print("LOADING FGDs TOOK: " .. (SysTime() - start) .. " seconds")

--[[for k,v in pairs(classes) do
	if k:find("func_button") then
		print(k)
		PrintTable(v,1)
	end
end]]

FGDClasses = classes

function GetFGDClass(class)

	return FGDClasses[class]

end

function CategorizedIO(class, keys, out)

	keys = keys or { inputs = {}, outputs = {} }
	out = out or { inputs = {}, outputs = {} }

	for _,v in ipairs(class.baseclasses) do
		local fgd = FGDClasses[v]
		CategorizedIO(fgd, keys, out)
	end

	local t = {}
	for k,v in pairs(class.inputs) do
		if keys.inputs[k] then continue end
		keys.inputs[k] = true
		t[#t+1] = k
	end

	if #t > 0 then
		table.sort(t)
		table.insert(out.inputs, 1, { class = class.classname, list = t })
	end

	local t = {}
	for k,v in pairs(class.outputs) do
		if keys.outputs[k] then continue end
		keys.outputs[k] = true
		t[#t+1] = k
	end

	if #t > 0 then
		table.sort(t)
		table.insert(out.outputs, 1, { class = class.classname, list = t })
	end

	return out

end

if SERVER then

	concommand.Add("fgdclass", function(p,c,a)

		if a[1] then

			local class = GetFGDClass(a[1])
			PrintTable(class)

		end

	end)

end

if CLIENT then

	surface.CreateFont("ToolClassNameHuge", {
		font		= "VCR OSD Mono",
		size		= 24,
		weight		= 500,
		antialias	= true
	})

	surface.CreateFont("ToolClassNameBig", {
		font		= "VCR OSD Mono",
		size		= 18,
		weight		= 500,
		antialias	= true
	})

	surface.CreateFont("ToolClassNameMed", {
		font		= "VCR OSD Mono",
		size		= 14,
		weight		= 500,
		antialias	= true
	})

	local tool_classes = {}
	local tool_textures = {}
	local point_textures = {}
	local point_materials = {}
	local generate_tool_textures = true
	local tex_size = 128

	local colors = {
		["func_breakable"] = Color(160,180,100),
		["func_breakable_surf"] = Color(140,180,90),
		["func_brush"] = Color(60,60,90),
		["func_button"] = Color(60,170,80),
		["func_conveyor"] = Color(150,170,80),
		["func_door"] = Color(40,80,120),
		["func_door_rotating"] = Color(40,100,120),
		["func_healthcharger"] = Color(10,220,90),
		["func_monitor"] = Color(40,30,120),
		["func_movelinear"] = Color(100,100,170),
		["func_physbox"] = Color(100,80,120),
		["func_platrot"] = Color(180,80,120),
		["func_rotating"] = Color(200,100,255),
		["func_tank"] = Color(200,100,40),
		["func_trackchange"] = Color(200,80,40),
		["func_tracktrain"] = Color(200,130,40),
		["func_train"] = Color(200,130,40),
		["func_traincontrols"] = Color(30,160,200),
		["trigger_autosave"] = Color(250,180,10),
		["trigger_changelevel"] = Color(200,180,10),
		["trigger_hurt"] = Color(130,0,0),
		["trigger_multiple"] = Color(120,80,60),
		["trigger_once"] = Color(100,50,60),
		["trigger_push"] = Color(100,100,200),
		["trigger_teleport"] = Color(70,100,100),
	}

	for k,v in pairs(FGDClasses) do
		if v.classtype == "SolidClass" then
			tool_classes[#tool_classes+1] = k
		end
	end

	local point_classes = {}
	for k,v in pairs(FGDClasses) do
		if v.classtype == "PointClass" then
			--point_classes[#point_classes+1] = { v.classname, v.editorkeys and v.editorkeys.iconsprite or nil }
			if v.editorkeys and v.editorkeys.iconsprite then
				local tex = v.editorkeys.iconsprite:sub(1,-5)
				point_textures[v.classname] = tex
				point_materials[v.classname] = Material(tex)
				--print(tex)
			else
				local tex = "editor/info_target"
				point_textures[v.classname] = tex
				point_materials[v.classname] = Material(tex)
			end
		end
	end

	table.sort(tool_classes)
	table.sort(point_classes, function(a,b) return a[1] < b[1] end)

	for k,v in pairs(point_textures) do

		point_materials[k] = CreateMaterial("io_point_material_" .. k, "UnlitGeneric", {
			["$basetexture"] = v,
			["$vertexcolor"] = 1,
			["$vertexalpha"] = 1,
			["$model"] = 1,
			["$additive"] = 1,
			["$nocull"] = 0,
			["$alpha"] = 0.5
		})

	end

	local function GenerateToolTexture(class)

		local tooltexrt = wt_irt.New("io_tooltex_" .. class, tex_size, tex_size)
			:EnableDepth(false,false)
			:EnableFullscreen(false)
			:EnablePointSample(false)
			:EnableMipmap(true)

		local parts = {}
		for x in class:gmatch("%w+") do
			parts[#parts+1] = x
		end

		render.PushRenderTarget(tooltexrt:GetTarget())
			cam.Start2D()

				local col = colors[class]

				surface.SetDrawColor(255,255,255,255)
				surface.DrawRect(0, 0, tex_size, tex_size)
				surface.SetDrawColor(col or Color(80,80,80,255))
				surface.DrawRect(2, 2, tex_size-4, tex_size-4)

				if #parts == 1 then
					draw.SimpleText(parts[1], "ToolClassNameBig", tex_size/2, tex_size/2, Color( 255, 255, 255, 255 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				else
					local font = #parts[1] > 6 and "ToolClassNameBig" or "ToolClassNameHuge"
					draw.SimpleText(parts[1]:upper(), font, tex_size/2, 10, Color( 255, 255, 255, 255 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end

				local y = tex_size/2 - (#parts - 2) * 10
				for i=2, #parts do
					local font = "Trebuchet18"
					draw.SimpleText(parts[i]:upper(), font, tex_size/2, y, Color( 255, 255, 255, 255 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					y = y + 20
				end

			cam.End2D()

			--render.BlurRenderTarget(rtdark:GetTarget(), 4, 4, 2)	
			--DrawColorModify( invert_color_mod )
		render.PopRenderTarget()

		tool_textures[class] = tooltexrt

	end

	function GetToolMaterial(class)

		local tex = tool_textures[class]
		if tex == nil then print("NO TOOL MATERIAL FOR: " .. tostring(class)) 
			if class ~= "trigger_multiple" then return GetToolMaterial("trigger_multiple") end
			return 
		end
		--if tex ~= nil then return tex:GetUnlitMaterial() end

		return CreateMaterial("io_brush_tooltex_" .. class, "UnlitGeneric", {
			["$basetexture"] = tex:GetIDString(),
			["$vertexcolor"] = 1,
			["$vertexalpha"] = 1,
			["$model"] = 1,
			["$additive"] = 1,
			["$nocull"] = 0,
			["$alpha"] = 0.5
		})

	end

	function GetEntityIconMaterial(class)

		return point_materials[class]

	end

	hook.Add("PreRender", "wt_io_prerender_tooltextures", function()

		if generate_tool_textures then

			generate_tool_textures = false

			for _,v in ipairs(tool_classes) do
				GenerateToolTexture(v)
			end			

		end

	end)

	hook.Add("HUDPaint", "wt_io_showtooltextures", function()

		if true then return end

		local x = 0
		local y = 0
		local size = 128

		for i=1, #tool_classes do

			local tooltex = tool_textures[tool_classes[i]]

			if tooltex then
				surface.SetDrawColor( 255, 255, 255, 255 )
				surface.SetMaterial( tooltex:GetUnlitMaterial() )
				surface.DrawTexturedRect(x, y, size, size)
				x = x + size
				if x > 1600 then 
					x = 0 y = y + size
				end
			end

		end

	end)

end