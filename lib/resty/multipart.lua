if not ngx
   or not ngx.config.nginx_configure():find('--with-pcre-jit', nil, true) then
  error('lua-resty-multipart requires ngx_lua with JIT PCRE support')
end

local setmetatable = setmetatable
local concat = table.concat
local remove = table.remove
local rawget = rawget
local pairs = pairs
local type = type
local match = string.match
local re_match = ngx.re.match
local re_find = ngx.re.find
local lower = string.lower
local fmt = string.format
local sub = string.sub
local new_tab

do
  local ok
  ok, new_tab = pcall(require, 'table.new')
  if not ok or type(new_tab) ~= 'function' then
    new_tab = function(narr, nrec) return {} end
  end
end

local _cd = 'content-disposition'

local _M = {
  _VERSION = '0.0.1'
}

--- Helpers
-- @section helpers

local function trim(s)
  return s:gsub('^%s+', ''):reverse():gsub('^%s+', ''):reverse()
end

local function split(s, token)
  local t = {}

  while true do
    local from, to, err = re_find(s, token, 'oj')
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

--- Serializers
-- @section serializers

do
  local function parse_part_headers(part_headers)
    local headers_t, err = split(trim(part_headers), '\\n')
    if err then return nil, nil, err end

    local name
    local t = new_tab(#headers_t, #headers_t)

    for i = 1, #headers_t do
      local header = trim(headers_t[i])

      if lower(sub(header, 1, #_cd)) == _cd then
        local m, err = re_match(header, 'name="(.*?)"', 'oj')
        if err then return nil, nil, err
        elseif not m then return nil, nil, 'could not parse part name' end
        name = m[1]
      end

      local m, err = re_match(header, '(.*?):\\s*(.*)', 'oj')
      if err then return nil, nil, err
      elseif not m or not m[1] or not m[2] then
        return nil, nil, 'could not parse header field'
      end

      t[#t+1] = header
      t[lower(m[1])] = m[2]
    end

    return name, t
  end

  function _M.unserialize(body, boundary)
    if not body then
      return nil, 'missing body'
    elseif not boundary then
      return nil, 'missing boundary'
    end

    local parts, err = split(body, '--' .. boundary)
    if err then return nil, err end

    if parts[#parts] ~= '--' then
      return nil, 'bad format'
    else
      parts[#parts] = nil
    end

    local res = new_tab(#parts, #parts)

    for i = 1, #parts do
      local part = trim(parts[i])

      local from, to, err = re_find(part, '^\\s*$', 'ojm')
      if err then return nil, err
      elseif not from and not to then return nil, 'could not find part body' end

      local part_headers = sub(part, 1, from-1)
      local part_body = sub(part, to+2, #part) -- +2: trim leading line jump

      local name, headers, err = parse_part_headers(part_headers)
      if err then return nil, err end

      local res_part = {
        name = name,
        idx = i,
        headers = setmetatable(headers, headers_mt),
        value = part_body
      }

      res[name] = res_part
      res[i] = res_part
    end

    return res
  end
end

function _M.serialize(parts, boundary)
  if not parts or #parts == 0 then
    return nil, 'empty data'
  elseif not boundary then
    return nil, 'missing boundary'
  end

  boundary = '--' .. boundary
  local buf = new_tab(#parts*4, 0) -- (boundary + [headers] + line jump + part)

  for i = 1, #parts do
    local part = parts[i]

    buf[#buf+1] = boundary
    for j = 1, #part.headers do
      buf[#buf+1] = part.headers[j]
    end
    buf[#buf+1] = '' -- <headers>\n<body>
    buf[#buf+1] = part.value
  end

  buf[#buf+1] = boundary .. '--'

  return concat(buf, '\n') -- todo: \r\n
end

--- Multipart helper
-- @section multipart_helper

local _mt = {}

function _M.new(body, boundary, content_type)
  if body and type(body) ~= 'string' then
    return nil, 'body must be a string'
  elseif boundary and type(boundary) ~= 'string' then
    return nil, 'boundary must be a string'
  elseif content_type and type(content_type) ~= 'string' then
    return nil, 'content_type must be a string'
  end

  if not boundary and content_type then
    boundary = match(content_type, 'boundary=(%S+)')
    if not boundary then
      return nil, 'could not retrieve boundary from content_type'
    end
  end

  local self = {
    body = body,
    data = nil,
    boundary = boundary,
    -- state boolean: determines if 'data' and 'body' are in sync
    sync = true
  }

  return setmetatable(self, _mt)
end

function _mt:decode()
  if not self.data then
    local t, err = _M.unserialize(self.body, self.boundary)
    if not t then return nil, err end
    self.data = t
  end

  return self.data
end

function _mt:encode()
  if not self.sync then
    if not self.data then
      return nil, 'no data to encode, must call decode() or add()'
    end

    self.body = _M.serialize(self.data, self.boundary)
    self.sync = true
  end

  return self.body
end

function _mt:add(name, headers_t, value)
  headers_t = headers_t or new_tab(1, 1)
  setmetatable(headers_t, headers_mt) -- facilitates header lookup for Content-Disposition

  if not headers_t['Content-Disposition'] then
    headers_t['Content-Disposition'] = fmt([[form-data; name="%s"]], name)
  end

  local headers = {
    fmt([[Content-Disposition: %s]], headers_t['Content-Disposition'])
  }

  for k, v in pairs(headers_t) do
    if lower(k) ~= 'content-disposition' then
      headers[#headers+1] = fmt([[%s: %s]], k, v)
    end
  end

  local t = {
    name = name,
    headers = headers,
    value = value
  }

  if not self.data then
    if self.body and self.boundary then
      local ok, err = self:decode()
      if not ok then
        return nil, 'could not decode given body: ' .. err
      end
    else
      self.data = new_tab(1, 1)
    end
  end

  self.data[#self.data+1] = t
  self.data[name] = t
  self.sync = false

  return t
end

function _mt:remove(name)
  if type(name) ~= 'string' then
    return nil, 'name must be a string'
  elseif not self.data then
    if self.body and self.boundary then
      local ok, err = self:decode()
      if not ok then
        return nil, 'could not decode given body: ' .. err
      end
    else
      self.data = new_tab(1, 1)
    end
  end

  local part = self.data[name]
  if part then
    remove(self.data, part.idx)
    for i = 1, #self.data do
      self.data[i].idx = i -- re-synchronize index shorthands
    end
    self.data[name] = nil
    self.sync = false
  end

  return true
end

function _mt:__index(key)
  if _mt[key] ~= nil then
    return _mt[key]
  end

  local data = rawget(self, 'data')
  if data then
    if type(key) == 'number' then
      return data[key]
    elseif sub(key, 1, 5) == 'part_' then
      return data[sub(key, 6, #key)]
    end
  end
end

function _mt:__tostring()
  local str, err = self:decode()
  if not str then error(err) end
  return str
end

return _M
