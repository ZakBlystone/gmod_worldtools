AddCSLuaFile()

-- Embedding this compressed .fgd data into a lua file to transmit to clients

--====== Copyright © 1996-2005, Valve Corporation, All rights reserved. =======
--
-- Purpose: Half-Life: Source & Half-Life Deathmatch: Source game definition file (.fgd) 
-- by ts2do (Updated by Dmx6 October 2007, by SiPlus June 2011 and by BlackShadow 2018)
--
--=============================================================================

local text = 
[[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
IqtMkyyNFGOn4Kum]]

wt_iocommon.parseFGDString(
	"halflife_source", 
	util.Decompress(util.Base64Decode(text)),
	"\n"
)