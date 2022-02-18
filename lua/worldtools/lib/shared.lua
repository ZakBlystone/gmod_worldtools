include("sh_gc.lua")
include("sh_statemachine.lua")
include("sh_struct.lua")
include("sh_task.lua")
include("sh_irt.lua")
include("sh_mesh.lua")
include("sh_csent.lua")
include("sh_mathutils.lua")
include("sh_matrix.lua")
include("sh_quat.lua")
include("sh_geomutils.lua")
include("sh_gfx.lua")
include("sh_statusui.lua")

include("sh_poly.lua")
include("sh_brush.lua")
include("sh_phy.lua")
include("sh_bsptypes.lua")

-- Needs to load before bsp
include("io/sh_iocommon.lua")
include("io/sh_ioindexing.lua")
include("io/sh_ionode.lua")
include("io/sh_iograph.lua")
include("io/sh_ionet.lua")
include("io/sh_iotrace.lua")
include("io/sh_iomove.lua")
include("io/sh_ioworld.lua")

include("sh_bsp.lua")
include("sh_bmodelmap.lua")
include("sh_bspquery.lua")

if SERVER then AddCSLuaFile("shared.lua") end