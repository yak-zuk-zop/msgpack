REBAR := $(shell which rebar3 2>/dev/null || which ./rebar3)

all: clean compile xref dialyzer lint tests

clean:
	${REBAR} clean

compile:
	${REBAR} compile

xref:
	${REBAR} xref

dialyzer:
	${REBAR} as test dialyzer

lint:
	$(REBAR) lint

tests:
	${REBAR} eunit
