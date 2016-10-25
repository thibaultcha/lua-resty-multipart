package = "lua-resty-multipart"
version = "0.0.1-1"
source = {
  url = "git://github.com/thibaultCha/lua-resty-multipart",
  tag = "0.0.1"
}
description = {
  summary = "",
  homepage = "https://github.com/thibaultcha/lua-resty-multipart",
  license = "MIT"
}
build = {
  type = "builtin",
  modules = {
    ["resty.multipart"] = "lib/resty/multipart.lua",
  }
}
