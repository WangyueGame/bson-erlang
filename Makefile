
REBAR ?= rebar3

all: clean compile xref eunit

clean compile xref eunit:
	@$(REBAR) $@
