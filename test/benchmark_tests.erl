-module(benchmark_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PCNT, 5).
-define(CNT, 10000).

%%-- tests --------------------------------------------------------------------

map_benchmark_test_() ->
    [{"map benchmark", [fun() ->
        Opts = [{map_format, Map}],
        Data = lists:duplicate(?CNT, test_utils:test_map(Map, ?PCNT)),
        S = ?debugTime("\tserialize", msgpack:pack(Data, Opts)),
        {ok, Data} = ?debugTime("\tdeserialize", msgpack:unpack(S, Opts)),
        ?debugFmt("for ~p KB test data(~p).", [byte_size(S) div 1024, Map])
    end || Map <- [map, jsx]]}].

t2b_b2t_benchmark_test() ->
    Data = lists:duplicate(?CNT, test_utils:test_data()),
    S = ?debugTime("\tserialize", term_to_binary(Data)),
    Data = ?debugTime("\tdeserialize", binary_to_term(S)),
    ?debugFmt("for ~p KB test data(t2b/b2t).", [byte_size(S) div 1024]).

benchmark_test_() ->
    [
        {timeout, 600, ?_assertEqual(ok, multirunner("jsx",
            fun(Data) ->
                msgpack:pack(Data, [{map_format, jsx}])
            end,
            fun(Data) ->
                msgpack:unpack(Data, [{map_format, jsx}])
            end
        ))},
        {timeout, 600, ?_assertEqual(ok, multirunner("maps",
            fun msgpack:pack/1,
            fun msgpack:unpack/1
        ))},
        {timeout, 600, ?_assertEqual(ok, multirunner("t2b/b2t",
            fun erlang:term_to_binary/1,
            fun erlang:binary_to_term/1
        ))}
    ].

%%-- internals ----------------------------------------------------------------

multirunner(What, Pack, Unpack) ->
    Data = lists:duplicate(?CNT, test_utils:test_data()),
    Packed = Pack(Data),
    Size = byte_size(Packed) div 1024,

    TotalPack = runner(Pack, Data, ?PCNT),
    TotalUnpack = runner(Unpack, Packed, ?PCNT),

    ?debugFmt("~.3fs / ~.3fs for ser/de ~p KB test data(~s x ~p).", [
        TotalPack / 1_000_000,
        TotalUnpack / 1_000_000,
        Size, What, ?PCNT
    ]),
    ok.

runner(Fun, Data, Count) ->
    Self = self(),
    [spawn(fun() ->
        {T, _} = timer:tc(Fun, [Data]),
        Self ! {p0, N, T}
    end) || N <- lists:seq(1, Count)],
    Times = [receive
        {p0, N, Time} ->
            Time
    end || N <- lists:seq(1, Count)],
    lists:sum(Times) / Count.
