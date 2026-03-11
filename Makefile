
REBAR ?= rebar3
BENCH_ITERATIONS ?= 100000

all: clean compile xref eunit

bench: compile
	@./scripts/bench_bson.escript --iterations $(BENCH_ITERATIONS)

clean compile xref eunit:
	@$(REBAR) $@
