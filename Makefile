.PHONY: test

test:
	@./rbusted

lint:
	@luacheck -q . \
		--std 'ngx_lua+busted' \
		--no-unused-args \
		--no-redefined

