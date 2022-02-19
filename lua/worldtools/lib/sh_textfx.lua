if SERVER then AddCSLuaFile() return end

module("wt_textfx", package.seeall)

local VMatrix = FindMetaTable("VMatrix")
local surface_setFont = surface.SetFont
local surface_setDrawColor = surface.SetDrawColor
local surface_setTextPos = surface.SetTextPos
local surface_setTextColor = surface.SetTextColor
local surface_getTextSize = surface.GetTextSize
local surface_drawText = surface.DrawText
local surface_drawRect = surface.DrawRect
local surface_drawOutlinedRect = surface.DrawOutlinedRect
local mtx_set = VMatrix.SetUnpacked
local cam_push = cam.PushModelMatrix
local cam_pop = cam.PopModelMatrix
local rad = math.pi / 180
local cos = math.cos
local sin = math.sin
local floor = math.floor
local ceil = math.ceil

-- Box
local _m = {}
_m.__index = _m

function _m:Pad(l,r,t,b)

	if not l then -- no padding
		l,r,t,b = 0,0,0,0
	elseif not r then -- all padding
		r,t,b = l,l,l
	elseif not t then -- horizontal, vertical
		l,r,t,b = l,l,r,r
	end

	self.w = self.w + (l+r)
	self.h = self.h + (t+b)
	self.x = self.x - l
	self.y = self.y - t
	return self

end

function _m:Draw(r,g,b,a)

	surface_setDrawColor(r,g,b,a)
	surface_drawRect(self.x,self.y,self.w,self.h)
	return self

end

function _m:DrawRounded(r,g,b,a,s)

	draw.RoundedBox((s or 0),self.x,self.y,self.w,self.h, Color(r,g,b,a))
	return self

end

function _m:HAlignTo(box, mode, offset)

	local ax, ay, aw, ah = box.x, box.y, box.w, box.h
	local bx, by, bw, bh = self.x, self.y, self.w, self.h

	local mx = offset or 0
	if mode == "before" then
		mx = mx + (ax - bx) - (bw)
	elseif mode == "left" then
		mx = mx + (ax - bx)
	elseif mode == "right" then
		mx = mx + (ax - bx) + aw - bw
	elseif mode == "after" then
		mx = mx + (ax - bx) + aw
	elseif mode == "center" then
		mx = mx + (ax - bx) + (aw-bw)/2
	end

	self.x = self.x + mx
	return self

end

function _m:VAlignTo(box, mode, offset)

	local ax, ay, aw, ah = box.x, box.y, box.w, box.h
	local bx, by, bw, bh = self.x, self.y, self.w, self.h

	local my = offset or 0
	if mode == "before" then
		my = my + (ay - by) - (bh)
	elseif mode == "top" then
		my = my + (ay - by)
	elseif mode == "bottom" then
		my = my + (ay - by) + ah - bh
	elseif mode == "after" then
		my = my + (ay - by) + ah
	elseif mode == "center" then
		my = my + (ay - by) + (ah-bh)/2
	end

	self.y = self.y + my
	return self

end

function _m:Shift(x,y)

	self.x = self.x + x
	self.y = self.y + y
	return self

end

function _m:Store()

	self.lx = self.x
	self.ly = self.y
	return self

end

function _m:Diff()

	return self.x - (self.lx or 0), self.y - (self.ly or 0)

end

function _m:Unpack()

	return self.x, self.y, self.w, self.h

end

local boxes = {}
local nextBox = 0
for i=1, 64 do
	local box = setmetatable({}, _m)
	boxes[#boxes+1] = box
end

function Box(x,y,w,h)

	local b = boxes[nextBox+1]
	nextBox = (nextBox+1) % #boxes

	if type(x) == "table" then
		b.x,b.y,b.w,b.h = x.x,x.y,x.w,x.h
	else
		b.x,b.y,b.w,b.h = x,y,w,h
	end

	return b

end

function ScreenBox()

	return Box( 0, 0, ScrW(), ScrH() )

end

local _min = math.min
local _max = math.max
function BuilderBox(...)

	local x0,y0,x1,y1 = math.huge,math.huge,-math.huge,-math.huge

	for i = 1, select('#', ...) do
		local b = select(i, ...) 
		local x,y,w,h = b:GetBox()
		x0 = _min(x0, x)
		y0 = _min(y0, y)
		x1 = _max(x1, x+w)
		y1 = _max(y1, y+h)
	end

	return Box(x0, y0, x1-x0, y1-y0)

end

function BuilderShift(x,...)

	local k,y = 1,0
	if type(x) == "table" then
		x,y = x:Diff()
	else
		k = 2
		x,y = x,select(1, ...)
	end

	for i = k, select('#', ...) do
		local b = select(i, ...) 
		b.x = b.x + x
		b.y = b.y + y
	end

end

function DrawBox(x,y,w,h,r,g,b,a)
	surface_setDrawColor(r,g,b,a)
	surface_drawRect(x,y,w,h)
end

-- Text Builder
local _boxm = _m
local _m = {}
_m.__index = function(s,k)

	if k == "tw" or k == "th" then
		if s.font then surface_setFont(s.font) end
		local tw, th = surface_getTextSize(rawget(s, "string"))
		rawset(s, "tw", tw)
		rawset(s, "th", th)
		return k == "tw" and tw or th
	end
	return _m[k] or _boxm[k]

end

function _m:Center()
	return self:HCenter():VCenter()
end

function _m:HCenter()
	self.x = self.x - self.tw/2
	return self
end

function _m:HRight()
	self.x = self.x - self.tw
	return self
end

function _m:VCenter()
	self.y = self.y - self.th/2
	return self
end

function _m:VBottom()
	self.y = self.y - self.th
	return self
end

function _m:Color(r,g,b,a)
	if type(r) == "table" then
		self.cr, self.cg, self.cb, self.ca = r,nil,nil,nil
	else
		self.cr, self.cg, self.cb, self.ca = r,g,b,a
	end
	return self
end

function _m:Box(l,r,t,b)
	if not l then -- no padding
		l,r,t,b = 0,0,0,0
	elseif not r then -- all padding
		r,t,b = l,l,l
	elseif not t then -- horizontal, vertical
		l,r,t,b = l,l,r,r
	end

	self.w = self.tw + (l+r)
	self.h = self.th + (t+b)
	self.x = self.x - l
	self.y = self.y - t
	return self
end

function _m:SetPos(x,y)
	self.x = x
	self.y = y
	return self
end

function _m:Draw()
	if self.font then surface_setFont(self.font) end
	local x,y = self.x, self.y
	if self.w ~= 0 then x = x - (self.tw - self.w)*0.5 end
	if self.h ~= 0 then y = y - (self.th - self.h)*0.5 end
	surface_setTextPos(x,y)
	surface_setTextColor(self.cr, self.cg, self.cb, self.ca)
	surface_drawText(self.string)
	return self
end

function _m:DrawBox(r,g,b,a)
	surface_setDrawColor(r,g,b,a)
	surface_drawRect(self:GetBox())
	return self
end

function _m:GetBox()
	return self.x, self.y, self.w, self.h
end

function _m:GetSize()
	return self.tw, self.th
end

local builders = {}
local nextBuilder = 0
for i=1, 64 do
	local builder = setmetatable({}, _m)
	builders[#builders+1] = builder
end

function Builder(str, font)

	assert(str ~= nil)

	local b = builders[nextBuilder+1]
	nextBuilder = (nextBuilder+1) % #builders

	b.x = 0
	b.y = 0
	b.w = 0
	b.h = 0
	b.tw = nil
	b.th = nil
	b.string = str
	b.cr, b.cg, b.cb, b.ca = 255,255,255,255
	b.color = nil
	b.font = font
	return b

end

local __scratchMatrix = Matrix()
local __pushedMatrix = false
local function PushMtx23(a0,a1,a2,b0,b1,b2)

	mtx_set( __scratchMatrix, 
		a0, a1, 0, a2,
		b0, b1, 0, b2,
		0, 0, 1, 0,
		0, 0, 0, 1 )

	cam_push( __scratchMatrix )
	__pushedMatrix = true

end

local function PopMtx()

	if __pushedMatrix then cam_pop() end
	__pushedMatrix = false

end

function MakeTiles( str, font )

	surface_setFont( font )

	local tiles = {}
	local tw, th = surface_getTextSize(str)

	local advance = 0
	for i=1, #str do

		local ch = str[i]
		local w,h = surface_getTextSize(ch)
		if str[i] ~= " " then
			local t = {
				x = advance + w/2,
				w = w/2, -- half-width
				h = h/2, -- half-height
				ch = ch,
			}
			if #tiles == 0 then
				t.tw = tw
				t.th = th
				t.font = font
			end
			tiles[#tiles+1] = t
		end

		advance = advance + w

	end

	return tiles

end

function TileForm(tile, x, y, r, sx, sy)

	x = x or 0
	y = y or 0
	r = r or 0
	sx = sx or 1
	sy = sy or 1

	local c = cos(r * rad)
	local s = sin(r * rad)

	local a0 = sx * c
	local a1 = sy * s
	local a2 = x - c * tile.w * sx - s * tile.h * sy
	local b0 = sx * -s
	local b1 = sy * c
	local b2 = y + s * tile.w * sx - c * tile.h * sy

	return a0, a1, a2, b0, b1, b2

end

function LayoutLeft( tiles, x, y )

	local out = {}

	local tw = tiles[1].tw
	local th = tiles[1].th
	for _, v in ipairs(tiles) do

		out[#out+1] = {
			t = v,
			x = x + v.x,
			y = y,
			r = 0,
			sx = 1,
			sy = 1,
			a = 1,
		}

	end

	return out

end

function LayoutRight( tiles, x, y )

	local out = {}

	local tw = tiles[1].tw
	local th = tiles[1].th
	for _, v in ipairs(tiles) do

		out[#out+1] = {
			t = v,
			x = x + v.x - tw,
			y = y,
			r = 0,
			sx = 1,
			sy = 1,
			a = 1,
		}

	end

	return out

end

function LayoutCentered( tiles, x, y )

	local out = {}

	local tw = tiles[1].tw
	local th = tiles[1].th
	for _, v in ipairs(tiles) do

		out[#out+1] = {
			t = v,
			x = x + v.x - tw * .5,
			y = y,
			r = 0,
			sx = 1,
			sy = 1,
			a = 1,
		}

	end

	return out

end

function DrawLayout(layout)

	surface_setFont( layout[1].t.font )

	render.PushFilterMag( TEXFILTER.ANISOTROPIC )
	render.PushFilterMin( TEXFILTER.ANISOTROPIC )

	for k,v in ipairs(layout) do

		PushMtx23( TileForm(v.t,v.x,v.y,v.r,v.sx,v.sy) )

		surface_setTextColor(v.cr or 255,v.cg or 255,v.cb or 255,255*v.a)
		surface_setTextPos( 0, 0 ) 
		surface_drawText( v.t.ch )

		--surface_drawOutlinedRect( 0, 0, v.w*2, v.h*2 )

		PopMtx()

	end

	render.PopFilterMag()
	render.PopFilterMin()

end

print("TEXTFX")