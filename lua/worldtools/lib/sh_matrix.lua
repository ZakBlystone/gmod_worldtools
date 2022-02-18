if SERVER then AddCSLuaFile("sh_matrix.lua") end

local meta = FindMetaTable("VMatrix")

local __kmap = {}
for k=1,16 do __kmap[k] = { math.ceil(k/4), ((k-1) % 4)+1 } end


local cvmeta = {}
cvmeta.__index = function( self, k )
	local m = rawget(self, "mtx")
	local r,c = unpack(__kmap[k])
	if type(m) ~= "table" then return rawget(self, "mtx"):GetField( r, c ) end
	return rawget(self, "mtx")[ r ][ c ]
end

cvmeta.__newindex = function( self, k, v )
	if type(k) == "string" then return rawset(self, k, v) end
	local m = rawget(self, "mtx")
	local r,c = unpack(__kmap[k])
	if type(m) ~= "table" then rawget(self, "mtx"):SetField( r, c, v ) return end
	rawget(self, "mtx")[ r ][ c ] = v
end

function MAccess(mtx)
	return setmetatable({mtx = mtx}, cvmeta)
end

function meta:Copy()

	return Matrix( self:ToTable() )

end

local _T = MAccess()

function meta:Transform3( vector, w, out )

	out = out or Vector()

	local x = vector.x
	local y = vector.y
	local z = vector.z
	w = w or 1

	_T.mtx = self
	local nx = x * _T[1 ] + y * _T[2 ] + z * _T[3 ] + w * _T[4 ]
	local ny = x * _T[5 ] + y * _T[6 ] + z * _T[7 ] + w * _T[8 ]
	local nz = x * _T[9 ] + y * _T[10] + z * _T[11] + w * _T[12]

	out.x = nx
	out.y = ny
	out.z = nz

	return out

end

function meta:DrawAxis( scale )

	if SERVER then return end

	gfx.renderAxis( self:GetTranslation(), self:GetForward(), self:GetRight(), self:GetUp(), scale )

end