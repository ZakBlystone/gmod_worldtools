AddCSLuaFile()
if SERVER then return end

module( "wt_statusui", package.seeall )

LoadIcon = Material("gui/progress_cog.png")
LoadStates = LoadStates or {}

local IconSize = ScreenScale(16)

surface.CreateFont("WTStatusFont", {
	font		= "VCR OSD Mono",
	size		= ScreenScale(8),
	weight		= 500,
	antialias	= true
})

surface.CreateFont("WTStatusFontSmall", {
	font		= "VCR OSD Mono",
	size		= ScreenScale(6),
	weight		= 500,
	antialias	= true
})

local Loading = false
local MainText = "LOADING"
local SubText = "SUBTEXT"
local Progress = 0
local ProgBar0 = {0,1}
local ProgBar1 = {0,1}

function SetLoading( loading )

	Loading = loading

end

function SetMainText( text )

	MainText = text

end

function SetSubText( text )

	SubText = text

end

function PostProgress()

	Progress = Progress + 1

end

function SetMainProgressBar(num, total)

	ProgBar1 = {num, total}

end

function SetSubProgressBar(num, total)

	ProgBar0 = {num, total}

end

local alpha = 0
local lastText = ""
local function Paint()

	if Loading then
		alpha = math.min(alpha + FrameTime() * 4, 1)
	else
		alpha = math.max(alpha - FrameTime(), 0)
	end

	if alpha == 0 then return end

	local screen = wt_textfx.ScreenBox():Pad(-ScreenScale(15), -ScreenScale(50))

	local zone = wt_textfx.Box(0,0,ScreenScale(170), ScreenScale(40))
	:HAlignTo(screen, "right")
	:VAlignTo(screen, "bottom")
	:DrawRounded(0,0,0,100 * alpha,5)

	local icon = wt_textfx.Box(0,0,zone.h,zone.h)
	:HAlignTo(zone, "right")
	:VAlignTo(zone, "center")

	local top = wt_textfx.Builder(MainText, "WTStatusFont")
	:Box(8)
	:VAlignTo(zone, "top")
	:HAlignTo(zone, "left")
	:Color(255,255,255,255*alpha)
	:Draw()

	wt_textfx.Builder(SubText, "WTStatusFontSmall")
	:Box(8,2)
	:VAlignTo(top, "after")
	:HAlignTo(top, "left")
	:Color(255,255,255,255*alpha)
	:Draw()

	local prog1 = wt_textfx.Box(0,0,zone.w-icon.w,ScreenScale(4))
	:HAlignTo(zone, "left")
	:VAlignTo(zone, "bottom",-10)
	:Pad(-10,0)
	:Draw(255,255,255,10*alpha)

	local prog0 = wt_textfx.Box(0,0,zone.w-icon.w,ScreenScale(3))
	:HAlignTo(zone, "left")
	:VAlignTo(prog1, "before",-10)
	:Pad(-10,0)
	:Draw(255,255,255,10*alpha)

	prog0.w = prog0.w * (ProgBar0[1] / ProgBar0[2])
	prog0:Draw(255,255,255,255*alpha)

	prog1.w = prog1.w * (ProgBar1[1] / ProgBar1[2])
	prog1:Draw(255,255,255,255*alpha)

	-- Loading Icon
	surface.SetDrawColor(255, 255, 255, 255*alpha)
	surface.SetMaterial(LoadIcon)
	surface.DrawTexturedRectRotated(icon.x + icon.w/2, icon.y + icon.h/2, IconSize, IconSize, Progress * 5)

end

hook.Add("HUDPaint", "wt_status", Paint)