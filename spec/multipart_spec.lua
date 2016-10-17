local multipart = require "resty.multipart"

local function u(str)
  str = str:match("^%s*(%S.-%S*)%s*$")
  local level = math.huge
  local prefix, len = ""
  for pref in str:gmatch("\n(%s+)") do
    len = #prefix
    if len < level then
      level = len
      prefix = pref
    end
  end
  return (str:gsub("\n" .. prefix, "\n"):gsub("\n$", ""))
end

describe("unserialize()", function()
  local boundary = "---------------------------735323031399963166993862150"
  local body = u[[
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="text1"

    text default
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="text2"

    aωb
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="file1"; filename="a.txt"
    Content-Type: text/plain

    Content of a.txt.
    hello
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="file2"; filename="a.html"
    Content-Type: text/html

    <!DOCTYPE html><title>Content of a.html.</title>
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="file3"; filename="binary"
    Content-Type: application/octet-stream

    aωb
    -----------------------------735323031399963166993862150--
  ]]

  it("parses a multipart body", function()
    local res = assert(multipart.unserialize(body, boundary))

    assert.equal(5, #res)
    assert.equal("text1", res[1].name)
    assert.same({
      ["content-disposition"] = 'form-data; name="text1"'
    }, res[1].headers)
    assert.equal("text default", res[1].value)

    assert.equal("file1", res[3].name)
    assert.same({
      ["content-disposition"] = 'form-data; name="file1"; filename="a.txt"',
      ["content-type"] = "text/plain"
    }, res[3].headers)
    assert.equal("Content of a.txt.\nhello", res[3].value)
  end)

  it("aliases by name and part index", function()
    local res = assert(multipart.unserialize(body, boundary))

    for i = 1, #res do
      assert.equal(res[i], res[res[i].name])
    end
  end)

  it("sets case-insensitive __index metamethod for headers", function()
    local res = assert(multipart.unserialize(body, boundary))

    local part1 = res[1]
    assert.equal(part1.headers["Content-Disposition"], part1.headers["content-disposition"])
  end)
end)
