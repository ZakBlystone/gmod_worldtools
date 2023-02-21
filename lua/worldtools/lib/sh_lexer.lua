AddCSLuaFile()

module("wt_lexer", package.seeall)

local meta = {}
meta.__index = meta

local str_sub, str_find, str_gmatch = string.sub, string.find, string.gmatch
local function str_lookup(str) local t = {} for x in str_gmatch(str, ".") do t[x] = true end return t end
local function str_lookup_combine(...) local t = {} for _, x in ipairs({...}) do for k,v in pairs(x) do t[k] = v end end return t end
local whitespace = str_lookup(" \t\r\0")
local operators = str_lookup("@,!+&*$.=:[](){}\\")
local digits = str_lookup("0123456789")
local upper = str_lookup( "ABCDEFGHIJKLMNOPQRSTUVWXYZ" )
local lower = str_lookup( "abcdefghijklmnopqrstuvwxyz" )
local alpha = str_lookup_combine(upper, lower)
local alpha_num = str_lookup_combine(alpha, digits)

TOK_ERR = -2
TOK_EOF = -1
TOK_OP = 1
TOK_STRING = 2
TOK_INT = 3
TOK_IDENT = 4

function meta:Peek()
	return str_sub(self.str, self.ptr, self.ptr)
end

function meta:PutBack()
	self.ptr = self.ptr - 1
end

function meta:Char()
    local ch = str_sub(self.str, self.ptr, self.ptr)
    self.ptr = self.ptr + 1
	if self.ptr == self.len + 1 then self.eof = true end
    return ch
end

function meta:String()
	local e = str_find(self.str, "\"", self.ptr, true)
	if not e then return TOK_EOF end
	local str = str_sub(self.str, self.ptr, e-1)
	self.ptr = e+1

	if self:SkipSpaces() and self:Peek() == "\"" then
		self:Char()
		local tok, app = self:String()
		if tok ~= TOK_STRING then return TOK_ERR end
		return tok, str .. app
	end

	return TOK_STRING, str
end

function meta:SkipSpaces()
	local combine = false
	while not self.eof do
		local ch = self:Char()
		if whitespace[ch] then continue end
		if ch == '+' then combine = true continue end
		if ch == '\n' then self.line = self.line + 1 continue end
		if self.eof then return combine end
		if ch == '/' then
			if self:Peek() == '/' then
				while self:Char() ~= '\n' and not self.eof do end
				self.line = self.line + 1
			end
		else
			self:PutBack()
			return combine
		end
	end
end

function meta:RawToken()
	if self.stored_tok then
		local t,str = self.stored_tok, self.stored_str
		self.stored_tok, self.stored_str = nil, nil
		return t,str
	end
	self:SkipSpaces()
	if self.eof then return TOK_EOF end
	local ch = self:Char()
	if operators[ch] then return TOK_OP, ch end
	if ch == "\"" then return self:String() end
	if digits[ch] or ch == '-' then
		local k = ""
		repeat k, ch = k .. ch, self:Char()
		until (not digits[ch])
		if alpha[ch] or ch == '_' then return TOK_ERR end
		self:PutBack()
		return TOK_INT, k
	end

	local k = ""
	while (alpha[ch] or digits[ch] or ch == '_') and not self.eof do
		k, ch = k .. ch, self:Char()
	end
	self:PutBack()
	return TOK_IDENT, string.lower(k)
end

function meta:Token(expect, expect_str)
	local t, str = self:RawToken()
	if expect ~= nil and t ~= expect then return nil end
	if expect_str ~= nil and str ~= expect_str then return nil end
	return t, str
end

function meta:TokStr(expect)
	local _, str = self:Token(expect)
	return tostring(str)
end

function meta:TokInt()
	local _, str = self:Token(TOK_INT)
	if str then return tonumber(str) end
	return nil
end

function meta:TokPeek()
	if self.stored_tok == nil then
		self.stored_tok, self.stored_str = self:RawToken()
	end
	return self.stored_tok, self.stored_str
end

function meta:Store(tok, str)
	self.stored_tok = tok
	self.stored_str = str
end

function meta:SkipTo(tok, name)
	while not self.eof do
		local t, str = self:Token()
		if t == tok then
			if str == name then
				return self:Store(t, str)
			end
		end
	end
end

function New(str)
	return setmetatable({ str=str, ptr=1, len=#str, line=1 }, meta)
end