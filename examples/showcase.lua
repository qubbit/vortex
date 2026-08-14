-- A chunk exercising most of the language.
local M = {}
local unpack = table.unpack or unpack

local Account = {}
Account.__index = Account

function Account.new(owner, balance)
  local self = setmetatable({}, Account)
  self.owner = owner
  self.balance = balance or 0
  return self
end

function Account:deposit(amount)
  if amount <= 0 then
    error("deposit must be positive", 2)
  end
  self.balance = self.balance + amount
  return self
end

function Account:__tostring()
  return string.format("Account(%s, %.2f)", self.owner, self.balance)
end

-- Numeric tower
local nums = { 1, 1.5, .5, 1., 1e3, 1E-3, 0xff, 0x1p4, 0x.8p1 }

-- Strings and escapes
local strs = {
  'single', "double",
  [[long
string]],
  [==[nested ]] inside]==],
  "tab\there", "nl\nhere", "\65\66\67", "\x41", "\u{1F600}",
  "continue\z
   here",
}

-- Table constructors
local t = {
  1, 2, 3;
  name = "value",
  ["computed"] = 42,
  nested = { a = { b = { c = 1 } } },
  [1 + 1] = "two",
}

-- Control flow and goto
for i = 1, 10 do
  if i % 2 == 0 then goto continue end
  io.write(i, " ")
  ::continue::
end

for k, v in pairs(t) do
  if type(v) == "table" then
    for _, item in ipairs(v) do print(item) end
  end
end

local i = 0
while true do
  i = i + 1
  if i > 5 then break end
end

repeat
  i = i - 1
until i == 0

-- Varargs and multiple returns
local function sum(...)
  local total = 0
  for _, v in ipairs({...}) do total = total + v end
  return total, select('#', ...)
end

local total, count = sum(1, 2, 3)

-- Closures
local function counter()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end

-- Operators
local a, b = 7, 3
local ops = {
  a + b, a - b, a * b, a / b, a // b, a % b, a ^ b,
  a & b, a | b, a ~ b, a << b, a >> b, ~a,
  a < b, a <= b, a > b, a >= b, a == b, a ~= b,
  a .. b, #"str", not a, -a,
  a and b or nil,
  2^-3, -2^2,
}

-- Local attributes
local const_val <const> = 42
local file <close> = nil

-- Method chains and calls
local s = ("hello"):upper():lower()
print(#t, t.name, t["computed"])
Account.new("me", 10):deposit(5)

return M
