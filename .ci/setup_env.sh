set -e

#------------------------------
# Download OpenResty + Luarocks
#------------------------------
OPENRESTY_DOWNLOAD=$DOWNLOAD_CACHE/openresty-$OPENRESTY
LUAROCKS_DOWNLOAD=$DOWNLOAD_CACHE/luarocks-$LUAROCKS

mkdir -p $OPENRESTY_DOWNLOAD $LUAROCKS_DOWNLOAD

if [ ! "$(ls -A $OPENRESTY_DOWNLOAD)" ]; then
  pushd $DOWNLOAD_CACHE
    curl -L https://openresty.org/download/openresty-$OPENRESTY.tar.gz | tar xz
  popd
fi

if [ ! "$(ls -A $LUAROCKS_DOWNLOAD)" ]; then
  git clone https://github.com/keplerproject/luarocks.git $LUAROCKS_DOWNLOAD
fi

#-----------------------------
# Install OpenResty + Luarocks
#-----------------------------
OPENRESTY_INSTALL=$INSTALL_CACHE/openresty-$OPENRESTY
LUAROCKS_INSTALL=$INSTALL_CACHE/luarocks-$LUAROCKS

mkdir -p $OPENRESTY_INSTALL $LUAROCKS_INSTALL

if [ ! "$(ls -A $OPENRESTY_INSTALL)" ]; then
  pushd $OPENRESTY_DOWNLOAD
    ./configure \
      --prefix=$OPENRESTY_INSTALL \
      --with-pcre-jit \
      --without-http_coolkit_module \
      --without-http_coolkit_module \
      --without-lua_resty_dns \
      --without-lua_resty_lrucache \
      --without-lua_resty_upstream_healthcheck \
      --without-lua_resty_websocket \
      --without-lua_resty_upload \
      --without-lua_resty_string \
      --without-lua_resty_mysql \
      --without-lua_resty_redis \
      --without-http_redis_module \
      --without-http_redis2_module \
      --without-lua_redis_parser
    make
    make install
  popd
fi

if [ ! "$(ls -A $LUAROCKS_INSTALL)" ]; then
  pushd $LUAROCKS_DOWNLOAD
    git checkout v$LUAROCKS
    ./configure \
      --prefix=$LUAROCKS_INSTALL \
      --lua-suffix=jit \
      --with-lua=$OPENRESTY_INSTALL/luajit \
      --with-lua-include=$OPENRESTY_INSTALL/luajit/include/luajit-2.1
    make build
    make install
  popd
fi

export PATH=$PATH:$OPENRESTY_INSTALL/nginx/sbin:$OPENRESTY_INSTALL/bin:$LUAROCKS_INSTALL/bin

eval `luarocks path`

luarocks install busted
luarocks install luacheck
#luarocks install luacov
#luarocks install luacov-coveralls

resty -V
luarocks --version
