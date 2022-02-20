if SERVER then AddCSLuaFile("sh_matrix.lua") end

local meta = FindMetaTable("VMatrix")

function meta:Copy()

	return Matrix( self:ToTable() )

end

function meta:Transform3( vector, w, out )

	out = out or Vector()

	local x,y,z = vector:Unpack()
	local m1,m2,m3,m4,m5,m6,m7,m8,m9,m10,m11,m12 = self:Unpack()
	w = w or 1

	local nx = x * m1 + y * m2 + z * m3 + w * m4
	local ny = x * m5 + y * m6 + z * m7 + w * m8
	local nz = x * m9 + y * m10 + z * m11 + w * m12

	out:SetUnpacked(nx, ny, nz)
	return out

end

function meta:DrawAxis( scale )

	if SERVER then return end

	gfx.renderAxis( self:GetTranslation(), self:GetForward(), self:GetRight(), self:GetUp(), scale )

end