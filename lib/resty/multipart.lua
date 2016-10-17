local setmetatable = setmetatable
local rawget = rawget
--local re_gmatch = ngx.re.gmatch
local re_match = ngx.re.match
local re_find = ngx.re.find
--local re_sub = ngx.re.sub
local lower = string.lower
--local match = string.match
local sub = string.sub

local _cd = 'content-disposition'

local function trim(s)
  return s:gsub('^%s+', ''):reverse():gsub('^%s+', ''):reverse()
end

local function split(s, token)
  local t = {}

  while true do
    local from, to, err = re_find(s, token)
    if err then return nil, err
    elseif not from and not to then break end

    local part = sub(s, 1, from-1)
    if part ~= '' then
      t[#t+1] = part
    end

    s = sub(s, to+1, #s)
  end

  t[#t+1] = s

  return t
end

local headers_mt = {
  __index = function(self, k)
    return rawget(self, lower(k))
  end
}

local function parse_part_headers(part_headers)
  local headers_t, err = split(trim(part_headers), '\\n')
  if err then return nil, nil, err end

  local name
  local t = {}

  for i = 1, #headers_t do
    local header = trim(headers_t[i])

    if lower(sub(header, 1, #_cd)) == _cd then
        local m, err = re_match(header, 'name="(.*?)"')
        if err then return nil, nil, err
        elseif not m then return nil, nil, 'no name' end
        name = m[1]
    end

    local m, err = re_match(header, '(.*?):\\s*(.*)')
    if err then return nil, nil, err
    elseif not m or not m[1] or not m[2] then
      return nil, nil, 'bad format'
    end

    t[lower(m[1])] = m[2]
  end

  return name, t
end

local _M = {}

local function unserialize(body, boundary)
  local parts, err = split(body, '\\-\\-'..boundary)
  if err then return nil, err end

  if parts[#parts] ~= '--' then
    return nil, 'bad format'
  else
    parts[#parts] = nil
  end

  local res = {}

  for i = 1, #parts do
    local part = trim(parts[i])

    local from, to, err = re_find(part, '^\\s*$', 'm')
    if err then return nil, err
    elseif not from and not to then return nil, 'bad format' end

    local part_headers = sub(part, 1, from-1)
    local part_body = sub(part, to+2, #part) -- +2: trim leading line jump

    local name, headers, err = parse_part_headers(part_headers)
    if err then return nil, err end

    local res_part = {
      name = name,
      headers = setmetatable(headers, headers_mt),
      value = part_body
    }

    res[name] = res_part
    res[i] = res_part
  end

  return res
end

local function serialize(t, boundary)

end

_M.unserialize = unserialize

return _M
