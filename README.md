# lua-resty-multipart

![Module Version][badge-version-image]
[![Build Status][badge-travis-image]][badge-travis-url]

multipart/form-data MIME type parser optimized for
[OpenResty](https://openresty.org) with JIT PCRE.

**Note**: while this library is an improvement over some other ones out there,
it is not implemented in a streaming fashion unlike, for instance,
[lua-resty-upload](https://github.com/openresty/lua-resty-upload).
This means that your bodies must be accumulated in the Lua land, potentially
exhausting the Lua VM memory. We shall provide a `resty.multipart.streaming`
module for downstream/upstream streamed parsing.

### Table of Contents

* [Motivation](#motivation)
* [Usage](#usage)
* [Installation](#installation)
* [Documentation](#documentation)
* [License](#license)

### Motivation

TODO

[Back to TOC](#table-of-contents)

### Usage

Simple encoder/decoder:
```lua
local multipart = require 'resty.multipart'

-- decoding
local res = assert(multipart.unserialize(body?, boundary?))
for i, part in ipairs(res) do
  print(part.name)
end

-- encoding
local body = assert(multipart.serialize(
{
  name = 'part1',
  headers = {['Content-Disposition'] = 'form-data; name="part1"'},
  value = 'hello world'
},
{
  name = 'part2',
  headers = {['Content-Disposition'] = 'form-data; name="part2"'},
  value = 'foo'
}
), '------boundary')
```

Multipart helper:
```lua
local multipart = require 'resty.multipart'

local m = assert(multipart.new(body?, boundary?, content_type?))

-- decoding
local res = assert(m:decode())

-- modifying
assert(m:add('new_part', {['Content-Type'] = 'text/plain'}, 'hello world'))
assert(m:remove('name'))

-- encoding
local new_body = assert(m:encode())
```

[Back to TOC](#table-of-contents)

### Installation

TODO

[Back to TOC](#table-of-contents)

### Documentation

TODO

[Back to TOC](#table-of-contents)

### License

Work licensed under the MIT License.

[Back to TOC](#table-of-contents)

[badge-travis-url]: https://travis-ci.org/thibaultcha/lua-resty-multipart
[badge-travis-image]: https://travis-ci.org/thibaultcha/lua-resty-multipart.svg?branch=master

[badge-version-image]: https://img.shields.io/badge/version-0.0.1-blue.svg?style=flat
