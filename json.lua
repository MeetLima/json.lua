local M = {
    is_lima = true,
    _version = "0.2.0",
    PRETTY_PRINT = true,
}

local fmt = string.format


--- Encode ---

local encode

local escape_char_map = {
    [ "\\" ] = "\\\\",
    [ "\"" ] = "\\\"",
    [ "\b" ] = "\\b",
    [ "\f" ] = "\\f",
    [ "\n" ] = "\\n",
    [ "\r" ] = "\\r",
    [ "\t" ] = "\\t",
}

local escape_char_map_inv = { [ "\\/" ] = "/" }
for k, v in pairs(escape_char_map) do
    escape_char_map_inv[v] = k
end

local function escape_char(c)
    return escape_char_map[c] or fmt("\\u%04x", c:byte())
end

local function encode_nil()
    return "null"
end

local ident_cache = {}
local function s_ident(n)
    if not ident_cache[n] then
        local r = {}
        for _ = 1, n do r[#r+1] = "  " end
        ident_cache[n] = table.concat(r)
    end
    return ident_cache[n]
end

local function complex_ident(val, ident, left, right)
    if ident then
        return table.concat {
            left, "\n", s_ident(ident + 1),
            table.concat(val, ",\n" .. s_ident(ident + 1)),
            "\n", s_ident(ident), right
        }
    else
        return left .. table.concat(val, ",") .. right
    end
end

function M.should_treat_as_array(val)
    if val[1] == nil and next(val) ~= nil then
        return false
    end
    local n = 0
    for k in pairs(val) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #val
end

function M.object_key_to_string(k)
    if type(k) == "number" then
        k = tostring(k)
    end
    if type(k) ~= "string" then
        error(fmt("invalid table: key of type %s found", type(k)))
    end
    return k
end

local function encode_table(val, stack, ident)
    local res = {}

    -- Circular reference?
    if stack[val] then error("circular reference") end

    stack[val] = true

    if M.should_treat_as_array(val) then
        -- Encode. We ident only if the first element is an array.
        local must_ident = ident and type(val[1]) == "table"
        for _, v in ipairs(val) do
            v = encode(v, stack, must_ident and ident + 1)
            table.insert(res, v)
        end
        stack[val] = nil
        return complex_ident(res, must_ident and ident, "[", "]")
    else
        -- Treat as an object
        for k, v in pairs(val) do
            k = M.object_key_to_string(k)
            v = encode(v, stack, ident and ident + 1)
            table.insert(res, encode(k, stack) .. ":" .. v)
        end
        stack[val] = nil
        return complex_ident(res, ident, "{", "}")
    end
end

local function encode_string(val)
    return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_number(val)
  -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then
        error("unexpected number value '" .. tostring(val) .. "'")
    end
    if math.type and math.type(val) == "integer" then
        return fmt("%d", val)
    end
    return fmt("%.14g", val)
end

local type_func_map = {
    [ "nil" ] = encode_nil,
    [ "table" ] = encode_table,
    [ "string" ] = encode_string,
    [ "number" ] = encode_number,
    [ "boolean" ] = tostring,
}

encode = function(val, stack, ident)
  local t = type(val)
  local f = type_func_map[t]
  if f then
      return f(val, stack, ident)
  end
  error("unexpected type '" .. t .. "'")
end

function M.encode(val, pretty)
  if pretty == nil then pretty = M.PRETTY_PRINT end
  return ( encode(val, {}, pretty and 0 or nil) )
end


--- Decode ---


local parse

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
        res[ select(i, ...) ] = true
    end
    return res
end

local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals = create_set("true", "false", "null")

local literal_map = {
    [ "true"  ] = true,
    [ "false" ] = false,
    [ "null"  ] = nil,
}

local function next_char(str, idx, set, negate)
    for i = idx, #str do
        if set[str:sub(i, i)] ~= negate then
            return i
        end
    end
    return #str + 1
end

local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
      col_count = col_count + 1
      if str:sub(i, i) == "\n" then
          line_count = line_count + 1
          col_count = 1
      end
  end
  error( fmt("%s at line %d col %d", msg, line_count, col_count) )
end

local function parse_unicode_escape(s)
    local n1 = tonumber( s:sub(3, 6),  16 )
    local n2 = tonumber( s:sub(9, 12), 16 )
    -- Surrogate pair?
    if n2 then
        return utf8.char((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
        return utf8.char(n1)
    end
end

local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
        local x = str:byte(j)
        if x < 32 then
            decode_error(str, j, "control character in string")
        end
        if last == 92 then -- "\\" (escape char)
            if x == 117 then -- "u" (unicode escape sequence)
                local hex = str:sub(j + 1, j + 5)
                if not hex:find("%x%x%x%x") then
                    decode_error(str, j, "invalid unicode escape in string")
                end
                if hex:find("^[dD][89aAbB]") then
                    has_surrogate_escape = true
                else
                    has_unicode_escape = true
                end
            else
                local c = string.char(x)
                if not escape_chars[c] then
                    decode_error(str, j, "invalid escape char '" .. c .. "' in string")
                end
                has_escape = true
            end
            last = nil
        elseif x == 34 then -- '"' (end of string)
            local s = str:sub(i + 1, j - 1)
            if has_surrogate_escape then
                s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
            end
            if has_unicode_escape then
                s = s:gsub("\\u....", parse_unicode_escape)
            end
            if has_escape then
                s = s:gsub("\\.", escape_char_map_inv)
            end
            return s, j + 1
        else
            last = x
        end
    end
    decode_error(str, i, "expected closing quote for string")
end

local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then
        decode_error(str, i, "invalid number '" .. s .. "'")
    end
    return n, x
end

local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
        decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
end

local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
        local x
        i = next_char(str, i, space_chars, true)
        -- Empty / end of array?
        if str:sub(i, i) == "]" then
            i = i + 1
            break
        end
        -- Read token
        x, i = parse(str, i)
        res[n] = x
        n = n + 1
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "]" then break end
        if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
end

local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
        local key, val
        i = next_char(str, i, space_chars, true)
        -- Empty / end of object?
        if str:sub(i, i) == "}" then
            i = i + 1
            break
        end
        -- Read key
        if str:sub(i, i) ~= '"' then
            decode_error(str, i, "expected string for key")
        end
        key, i = parse(str, i)
        -- Read ':' delimiter
        i = next_char(str, i, space_chars, true)
        if str:sub(i, i) ~= ":" then
            decode_error(str, i, "expected ':' after key")
        end
        i = next_char(str, i + 1, space_chars, true)
        -- Read value
        val, i = parse(str, i)
        -- Set
        res[key] = val
        -- Next token
        i = next_char(str, i, space_chars, true)
        local chr = str:sub(i, i)
        i = i + 1
        if chr == "}" then break end
        if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
end

local char_func_map = {
    [ '"' ] = parse_string,
    [ "0" ] = parse_number,
    [ "1" ] = parse_number,
    [ "2" ] = parse_number,
    [ "3" ] = parse_number,
    [ "4" ] = parse_number,
    [ "5" ] = parse_number,
    [ "6" ] = parse_number,
    [ "7" ] = parse_number,
    [ "8" ] = parse_number,
    [ "9" ] = parse_number,
    [ "-" ] = parse_number,
    [ "t" ] = parse_literal,
    [ "f" ] = parse_literal,
    [ "n" ] = parse_literal,
    [ "[" ] = parse_array,
    [ "{" ] = parse_object,
}

parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then
        return f(str, idx)
    end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
end

function M.decode(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    return ( parse(str, next_char(str, 1, space_chars, true)) )
end


--- Module ---

return M
