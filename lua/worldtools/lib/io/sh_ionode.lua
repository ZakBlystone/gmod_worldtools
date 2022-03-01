AddCSLuaFile()

module( "wt_ionode", package.seeall )

G_IONODE_META = G_IONODE_META or {}

local meta = G_IONODE_META
meta.__index = meta

local function getBrushes(bspNode)

	local brushes = {}
	if bspNode then
		if bspNode.children then
			for _, v in pairs(bspNode.children) do
				table.Add(brushes, getBrushes(v))
			end
		end

		if bspNode.brushes then
			for _, b in pairs(bspNode.brushes) do
				table.insert(brushes, b:Copy(true))
			end
		end
	end

	return brushes

end

local function createBrushMesh(material, brushes)

	-- Update the current mesh
	local bmesh = wt_mesh.ManagedMesh(material)
	local vertices = {}
	local texScale = 16

	-- Add vertices for every side
	local to_brush = Vector() --brush.center
	for _, brush in pairs(brushes) do
		for _, side in pairs(brush.sides) do
			if not side.winding then continue end

			local texinfo = side.texinfo
			local texdata = texinfo.texdata
			--side.winding:Move( to_brush )
			side.winding:EmitMesh(
				texinfo.textureVecs:GetNormalized(), 
				texinfo.lightmapVecs:GetNormalized(), 
				texScale, 
				texScale, -to_brush, vertices)
			--side.winding:Move( -to_brush )
		end
	end

	-- Combine into single mesh
	bmesh:BuildFromTriangles(vertices)
	return bmesh

end

function meta:Init( ent, graph )

	self.ent = ent
	self.name = ent.targetname
	self.classname = ent.classname
	self.pos = ent.origin or Vector(0,0,0)
	self.angles = ent.angles or Angle(0,0,0)
	self.index = ent.index
	self.parentname = ent.parentname
	self.onMoved = {}
	self.graph = graph
	self.lastRenderTime = 0

	self:MakeClientEntity()
	return self

end

function meta:MakeClientEntity()

	if not CLIENT then return end

	local me = self

	local ent = self.ent
	local validModel = ent.model and string.len(ent.model) > 0 and ent.model[1] == "*"
	local brushMaterial = validModel and wt_iocommon.GetToolMaterial(ent.classname)
	if brushMaterial and validModel then

		local modelent = wt_csent.ManagedCSEnt("ionode_" .. self.index, ent.model)

		modelent:SetPos(ent.origin or Vector(0,0,0))
		local min, max = modelent:GetModelBounds()
		modelent:SetRenderBounds(min, max)
		modelent:SetNoDraw(false)
		modelent:SetRenderMode(RENDERMODE_TRANSTEXTURE)


		local brushes = {}
		if ent.bmodel then
			brushes = getBrushes(ent.bmodel.headnode)

			for _, v in pairs(brushes) do
				for _, side in pairs(v.sides) do
					side.plane.dist = side.plane.dist - 0.25
				end

				v:CreateWindings()
			end
		end

		modelent.IOBrushMesh = createBrushMesh(brushMaterial, brushes)
		modelent.IOBrushMaterial = brushMaterial
		modelent.IOBrushMatrix = Matrix()

		function modelent:RenderOverride()

			if not wt_ioworld.ShouldDrawIOView() then return end
			if not me:ExistsOnServer() then return end

			local mtx = self.IOBrushMatrix
			mtx:SetTranslation(self.RenderPos or self:GetPos() )
			mtx:SetAngles(self.RenderAngles or self:GetAngles() )
			cam.PushModelMatrix(mtx)
				render.SetMaterial(self.IOBrushMaterial)
				render.SetColorModulation(1, 1, 1)
				self.IOBrushMesh:Draw()
			cam.PopModelMatrix()
			me.lastRenderTime = RealTime()

		end

		self.model = modelent
		self.localBounds = {min, max}

	elseif self:HasIcon() then

		local iconent = wt_csent.ManagedCSEnt("ionode_" .. self.index, Model("models/Combine_Helicopter/helicopter_bomb01.mdl"))
		local icon = wt_iocommon.GetEntityIconMaterial( self.classname )

		local min, max = Vector(-4,-4,-4), Vector(4,4,4)

		iconent:SetPos(ent.origin or Vector(0,0,0))
		iconent:SetRenderBounds(min, max)
		iconent:SetNoDraw(false)
		iconent:SetRenderMode(RENDERMODE_NORMAL)

		function iconent:RenderOverride()

			if not wt_ioworld.ShouldDrawIOView() then return end
			if not me:ExistsOnServer() then return end

			if icon ~= nil then

				render.SetMaterial(icon)
				render.DrawSprite(self.RenderPos or self:GetPos(), 8, 8)
				me.lastRenderTime = RealTime()

			end

		end
		self.model = iconent
		self.is_icon = true
		self.localBounds = {min, max}

	elseif validModel then

		print("NO MATERIAL FOR CLASS: " .. ent.classname .. " : " .. tostring(ent.model))

	end

end

function meta:GetPos() 

	local ent = self:GetEntity()
	if IsValid(ent) then return ent:GetPos() end

	local parent = self:GetParent()
	if parent ~= nil then
		local preal = parent:GetEntity()
		if IsValid(preal) then
			local lpos, lang = preal:GetPos(), preal:GetAngles()
			local opos, oang = WorldToLocal(self.pos, self.angles, parent.pos, parent.angles)
			local pos, ang = LocalToWorld(opos, oang, lpos, lang)
			return pos
		end
	end

	return self.pos

end

function meta:GetAngles() 

	local ent = self:GetEntity()
	if IsValid(ent) then return ent:GetAngles() end

	local parent = self:GetParent()
	if parent ~= nil then
		local preal = parent:GetEntity()
		if IsValid(preal) then
			local lpos, lang = preal:GetPos(), preal:GetAngles()
			local opos, oang = WorldToLocal(self.pos, self.angles, parent.pos, parent.angles)
			local pos, ang = LocalToWorld(opos, oang, lpos, lang)
			return ang
		end
	end

	return self.angles

end

function meta:GetMatrix(mtx)

	mtx = mtx or Matrix()

	if self.is_icon then
		mtx:SetTranslation(self.pos)
		mtx:SetAngles(self.angles)
		return mtx
	end

	local ent = self:GetEntity()
	if IsValid(ent) then
		mtx:SetTranslation(ent:GetPos())
		mtx:SetAngles(ent:GetAngles())
		return mtx
	end

	local parent = self:GetParent()
	if parent ~= nil then
		local preal = parent:GetEntity()
		if IsValid(preal) then
			local lpos, lang = preal:GetPos(), preal:GetAngles()
			local opos, oang = WorldToLocal(self.pos, self.angles, parent.pos, parent.angles)
			local pos, ang = LocalToWorld(opos, oang, lpos, lang)
			mtx:SetTranslation(pos)
			mtx:SetAngles(ang)
			return mtx
		end
	end

	mtx:SetTranslation(self.pos)
	mtx:SetAngles(self.angles)
	return mtx

end

function meta:GetIndex() return self.index end
function meta:GetName() return self.name or "<" .. self:GetClass() .. "[" .. self.index .. "]>" end
function meta:GetClass() return self.classname or "__unknown__" end
function meta:Outputs() return self.graph:NodeOutputs(self) end
function meta:Inputs() return self.graph:NodeInputs(self) end
function meta:GetRawOutputs() return self.ent.outputs or {} end
function meta:GetEntity() return ents.GetMapCreatedEntity(self.index+1234) end
function meta:ExistsOnServer() return ents.ExistsOnServer(self.index+1234) end
function meta:GetParent() return self.parent end
function meta:GetLocalBounds() return unpack(self.localBounds or {}) end
function meta:HasBounds() return self.localBounds ~= nil end
function meta:WasRecentlyRendered() return self.lastRenderTime ~= nil and RealTime() - self.lastRenderTime < 0.1 end 

function meta:Moved()
	for _,v in pairs(self.onMoved) do
		v()
	end
end

function meta:FireInput(func, activator, caller, delay, param)

	self.graph:GetEventQueue():AddRaw(self, func, activator, caller, delay, param)

end

function meta:FireOutput( event, activator, caller )

	for _,v in self:Outputs() do

		if v.event == event then

			v:Fire(activator, caller)

		end

	end

end

local angleIdent = Angle(0,0,0)

function meta:Update()

	self.existsOnServerCached = self:ExistsOnServer()

	if not self.existsOnServerCached then return end
	if self.is_icon then return end -- Icons don't move

	local model = self.model
	if model then

		--if self.ent.classname == "func_movelinear" then
		local real = self:GetEntity()
		local pos, ang
		if IsValid(real) then
			pos, ang = real:GetPos(), real:GetAngles()
		else
			pos, ang = self.pos, self.angles
		end

		local parent = self.parent
		if parent ~= nil then
			local preal = parent:GetEntity()
			if IsValid(preal) then
				local lpos, lang = preal:GetPos(), preal:GetAngles()
				local opos, oang = WorldToLocal(self.pos, self.angles, parent.pos, parent.angles)
				pos, ang = LocalToWorld(opos, oang, lpos, lang)
			end
		end

		if self.lastPos ~= pos then
			self:Moved()

			model.RenderPos = pos
			model:SetPos( pos )
		end

		if self.lastAng ~= ang then
			model.RenderAngles = ang
			model:SetAngles( ang )
		end

		self.lastPos = pos
		self.lastAng = ang

	end

end

function meta:HasIcon()

	return wt_iocommon.GetEntityIconMaterial( self.classname ) ~= nil

end

function meta:Draw()

	if self.model then

		self.model:RenderOverride()

	end

end

function meta:MatchesName( name )

	if self.name == name then return true end
	if self.name and string.Right(name, 1) == "*" then
		return string.find( self.name, string.sub( name, 1, -1 ) ) == 1
	end
	return false

end

function New(ent, graph)

	return setmetatable({}, meta):Init(ent, graph)

end
