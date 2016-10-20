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

describe("unserialize()", function()
  it("parses a multipart body", function()
    local res = assert(multipart.unserialize(body, boundary))

    assert.equal(5, #res)
    assert.equal("text1", res[1].name)
    assert.same({
      [1] = 'Content-Disposition: form-data; name="text1"',
      ["content-disposition"] = 'form-data; name="text1"'
    }, res[1].headers)
    assert.equal("text default", res[1].value)

    assert.equal("file1", res[3].name)
    assert.same({
      [1] = 'Content-Disposition: form-data; name="file1"; filename="a.txt"',
      [2] = "Content-Type: text/plain",
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

describe("serialize()", function()
  it("serializes a body to its original form", function()
    local res = assert(multipart.unserialize(body, boundary))
    local str = multipart.serialize(res, boundary)

    assert.equal(body, str)
  end)
end)

describe("multipart helper", function()
  describe("new()", function()
    it("creates a multipart helper", function()
      assert.has_no_error(multipart.new)
    end)

    it("sanitizes arguments", function()
      assert.error_matches(function()
        assert(multipart.new(123))
      end, "body must be a string", nil, true)

      assert.error_matches(function()
        assert(multipart.new("", 123))
      end, "boundary must be a string", nil, true)

      assert.error_matches(function()
        assert(multipart.new("", "", 123))
      end, "content_type must be a string", nil, true)
    end)

    it("retrieves the boundary from content-type", function()
      local content_type = string.format(u[[
        Content-Type: multipart/form-data; boundary=%s
      ]], boundary)
      local m = assert(multipart.new(body, nil, content_type))
      assert.equal(boundary, m.boundary)
    end)

    it("errors if cannot retrieve boundary from content-type", function()
      assert.error_matches(function()
        assert(multipart.new(body, nil, "foobar"))
      end, "could not retrieve boundary from content_type", nil, true)
    end)

    it("ignores retrieving the boundary if content_type is nil", function()
      assert.has_no_error(multipart.new, body)
    end)

    it("uses the given boundary over content-type", function()
      local content_type = string.format(u[[
        Content-Type: multipart/form-data; boundary=%s
      ]], boundary)
      local m = assert(multipart.new(body, "boundary", content_type))
      assert.equal("boundary", m.boundary)
    end)

    it("is lazy (no decoding unless asked)", function()
      spy.on(multipart, "unserialize")
      assert(multipart.new(body, "boundary"))

      assert.spy(multipart.unserialize).was_not_called()
    end)
  end)

  describe("decode()", function()
    it("decodes the given body if not previously decoded", function()
      local m = assert(multipart.new(body, boundary))
      local res = assert(m:decode())
      local expected = assert(multipart.unserialize(body, boundary))
      assert.same(expected, res)
    end)

    it("sets 'data' field", function()
      local m = assert(multipart.new(body, boundary))
      local res = assert(m:decode())
      assert.equal(res, m.data)
    end)

    it("errors if no 'body'", function()
      assert.error_matches(function()
        local m = assert(multipart.new())
        assert(m:decode())
      end, "missing body", nil, true)
    end)

    it("errors if no 'boundary'", function()
      assert.error_matches(function()
        local m = assert(multipart.new(body))
        assert(m:decode())
      end, "missing boundary", nil, true)
    end)

    it("does not re-decode once already decoded", function()
      spy.on(multipart, "unserialize")

      local m = assert(multipart.new(body, boundary))
      assert(m:decode())
      assert(m:decode())

      assert.spy(multipart.unserialize).was_called(1)
    end)
  end)

  describe("__index()", function()
    it("gets a part if key is a number", function()
      local m = assert(multipart.new(body, boundary))
      assert(m:decode())

      assert.equal(m.data[1], m[1])
      assert.equal(m.data[2], m[2])
    end)

    it("gets a part if key is prefixed with 'part_'", function()
      local m = assert(multipart.new(body, boundary))
      assert(m:decode())

      assert.truthy(m.data.text1)
      assert.truthy(m.data.text2)
      assert.equal(m.data.text1, m.part_text1)
      assert.equal(m.data.text2, m.part_text2)
    end)
  end)

  describe("add()", function()
    it("adds a part without a Content-Disposition header", function()
      local m = assert(multipart.new())
      m:add("my_part", nil, "hello world")

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_part"

        hello world
        -----------------------------735323031399963166993862150--
      ]], res)
    end)

    it("adds a part with custom headers", function()
      local m = assert(multipart.new())
      m:add("my_part", {["Content-Type"] = "text/plain"}, "hello world")

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_part"
        Content-Type: text/plain

        hello world
        -----------------------------735323031399963166993862150--
      ]], res)
    end)

    it("adds a part with a Content-Disposition header", function()
      local m = assert(multipart.new())
      m:add("my_part", {
        ["Content-Type"] = "text/plain",
        ["Content-Disposition"] = [[form-data; name="my_file"; filename="my_file"]]

      }, "contents of file")

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_file"; filename="my_file"
        Content-Type: text/plain

        contents of file
        -----------------------------735323031399963166993862150--
      ]], res)
    end)

    it("adds a part with a lower-cased Content-Disposition header", function()
      local m = assert(multipart.new())
      m:add("my_part", {
        ["Content-Type"] = "text/plain",
        ["content-disposition"] = [[form-data; name="my_file_2"; filename="my_file_2"]]

      }, "contents of file 2")

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_file_2"; filename="my_file_2"
        Content-Type: text/plain

        contents of file 2
        -----------------------------735323031399963166993862150--
      ]], res)
    end)

    it("appends to body if given", function()
      local m = assert(multipart.new(body, boundary))
      assert(m:add("my_part", {["Content-Type"] = "text/plain"}, "hello world"))

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
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
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_part"
        Content-Type: text/plain

        hello world
        -----------------------------735323031399963166993862150--
      ]], res)
    end)

    it("is possible to append multiple times", function()
      local m = assert(multipart.new())
      m:add("my_part", {["Content-Type"] = "text/plain"}, "hello world")
      m:add("my_part_2", {["Content-Type"] = "text/plain"}, "hello world again")

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_part"
        Content-Type: text/plain

        hello world
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="my_part_2"
        Content-Type: text/plain

        hello world again
        -----------------------------735323031399963166993862150--
      ]], res)
    end)
  end)

  describe("remove()", function()
    it("only accepts a string", function()
      local m = assert(multipart.new(body, boundary))

      assert.error_matches(function()
        assert(m:remove())
      end, "name must be a string", nil, true)

      assert.error_matches(function()
        assert(m:remove(123))
      end, "name must be a string", nil, true)
    end)

    it("removes a part", function()
      local m = assert(multipart.new(body, boundary))
      assert(m:decode())
      assert.truthy(m.part_text1)

      assert(m:remove("text1"))
      assert.is_nil(m.part_text1)

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
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
      ]], res)
    end)

    it("calls decode() if needed and possible", function()
      spy.on(multipart, "unserialize")

      local m = assert(multipart.new(body, boundary))
      assert(m:remove("text1"))
      assert.spy(multipart.unserialize).was_called(1)
    end)

    it("removes multiple parts", function()
      local m = assert(multipart.new(body, boundary))
      assert(m:decode())
      assert(m:remove("text1"))
      assert(m:remove("file2"))

      local res = assert(multipart.serialize(m.data, boundary))
      assert.equal(u[[
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="text2"

        aωb
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="file1"; filename="a.txt"
        Content-Type: text/plain

        Content of a.txt.
        hello
        -----------------------------735323031399963166993862150
        Content-Disposition: form-data; name="file3"; filename="binary"
        Content-Type: application/octet-stream

        aωb
        -----------------------------735323031399963166993862150--
      ]], res)
    end)
  end)

  describe("encode()", function()
    it("returns given body if no modifications", function()
      spy.on(multipart, "serialize")

      local m = assert(multipart.new(body, boundary))
      assert.equal(body, m:encode())
      assert.spy(multipart.serialize).was_not_called()
    end)

    describe("re-encode body if modifications only", function()
      it("with add()", function()
        spy.on(multipart, "serialize")

        local m = assert(multipart.new(body, boundary))
        assert(m:encode())
        assert.spy(multipart.serialize).was_not_called()

        assert(m:add("my_part", {["Content-Type"] = "text/plain"}, "hello world"))
        assert(m:encode())
        assert.spy(multipart.serialize).was_called(1)
        assert(m:encode())
        assert.spy(multipart.serialize).was_called(1)
      end)

      it("with remove()", function()
        spy.on(multipart, "serialize")

        local m = assert(multipart.new(body, boundary))
        assert(m:encode())
        assert.spy(multipart.serialize).was_not_called()

        assert(m:remove("text1"))
        assert(m:encode())
        assert.spy(multipart.serialize).was_called(1)
        assert(m:encode())
        assert.spy(multipart.serialize).was_called(1)
      end)
    end)
  end)

  describe("__tostring()", function()
    it("uses encode()", function()
      local m = assert(multipart.new(body, boundary))
      local res = assert(m:decode())
      local res_2 = tostring(m)
      assert.same(res, res_2)
    end)

    it("throws errors", function()
      assert.error_matches(function()
        local m = assert(multipart.new())
        tostring(m)
      end, "missing body", nil, true)
    end)
  end)
end)
