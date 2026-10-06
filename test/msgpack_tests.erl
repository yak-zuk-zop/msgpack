-module(msgpack_tests).

-import(msgpack, [
    pack/2,
    unpack/2,
    pack/1,
    unpack/1
]).

-import(test_utils, [
    str/2
]).

-dialyzer({nowarn_function, error_test_/0}).

-include_lib("eunit/include/eunit.hrl").

%%-- tests --------------------------------------------------------------------

basic_test_() ->
    [?_assertEqual({ok, T}, unpack(pack(T))) || T <- test_utils:test_data()].

int_test_() ->
    %% [{Int, ExpectedPackedSize}]
    Tests = [
        %% fixnum
        {-32, 1},
        %% int8
        {-33, 2}, {-128, 2},
        %% int16
        {-129, 3}, {-16#8000, 3},
        %% int32
        {-16#8001, 5}, {-16#80000000, 5},
        %% int64
        {-16#80000001, 9}, {-16#8000000000000000, 9}
    ],
    [{"int", fun() ->
        Binary = pack(Term),
        ?assertEqual(ExpectedSize, byte_size(Binary)),
        ?assertEqual({ok, Term}, unpack(Binary))
    end} || {Term, ExpectedSize} <- Tests].

float_unpacking_test_() ->
   [
        %% float 32
        ?_assertEqual({ok, nan}, unpack(<<16#CA, 16#FF, 16#FF, 16#FF, 16#FF>>)),
        ?_assertEqual({ok, positive_infinity}, unpack(<<16#CA, 16#7F, 16#80, 16#00, 16#00>>)),
        ?_assertEqual({ok, negative_infinity}, unpack(<<16#CA, 16#FF, 16#80, 16#00, 16#00>>)),

        %% float 64
        ?_assertEqual({ok, nan}, unpack(<<16#CB, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF>>)),
        ?_assertEqual({ok, positive_infinity}, unpack(<<16#CB, 16#7F, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>)),
        ?_assertEqual({ok, negative_infinity}, unpack(<<16#CB, 16#FF, 16#F0, 16#00, 16#00, 16#00, 16#00, 16#00, 16#00>>))
    ].

atom_test_() ->
    [
        {"allow_atom pack/[atom]", [
            ?_assertEqual(pack(atom, [{allow_atom, pack}]), pack(atom, [{allow_atom, [atom]}]))
        ]},
        {"allow_atom none/empty", [
            ?_assertEqual({error, {badarg, atom}}, pack(atom, [{allow_atom, none}])),
            ?_assertEqual({error, {badarg, atom}}, pack(atom, [{allow_atom, []}]))
        ]},
        {"atom_test", fun () ->
            Map1 = #{atom1 => atom1, atom2 => <<"binary2">>},
            Expected = #{<<"atom1">> => <<"atom1">>, <<"atom2">> => <<"binary2">>},
            Bin = pack(Map1),
            ?assertEqual({ok, Expected}, unpack(Bin)),
            ?assertEqual({ok, Map1}, unpack(Bin, [{allow_atom, [atom1, atom2]}]))
        end}
    ].

array_test_() ->
    [
        {"array with various length", [fun() ->
            List = lists:seq(1, N),
            ?assertEqual({ok, List}, unpack(pack(List)))
        end || N <- [0, 16, 16#010000]]}
    ].

map_test_() ->
    [
        {"map with various type and size", [fun() ->
            Opts = [{map_format, T}],
            Map = test_utils:test_map(T, S),
            Binary = pack(Map, Opts),
            ?assertEqual({ok, Map}, unpack(Binary, Opts))
        end || T <- [map, jsx], S <- [0, 16, 16#010000]]},

        {"map <=> jsx", fun() ->
            JSXMap = test_utils:test_map(jsx, 16),
            BinaryJSX = pack(JSXMap, [{map_format, jsx}]),
            Map = maps:from_list(JSXMap),
            Binary = pack(Map, [{map_format, map}]),
            ?assertEqual(BinaryJSX, Binary)
        end},

        {"default map_format", fun() ->
            Map = test_utils:test_map(map, 16),
            ?assertEqual({ok, Map}, unpack(pack(Map), [{map_format, map}]))
        end},

        {"nested", fun () ->
            %% {'type':"workers", 'data':[{'workerid': "std.1", 'slots':[] }]}
            Term = [
                {<<"type">>, <<"workers">>},
                {<<"data">>, [[
                    {<<"workerid">>, <<"std.1">>},
                    {<<"slots">>, []}
                ]]}
            ],
            Opts = [{map_format, jsx}, {spec, new}],
            ?assertEqual({ok, Term}, unpack(pack(Term, Opts), Opts))
        end}
    ].

error_test_() ->
    [
        {"badarg tuple", fun() ->
            Term = {"hoge", "hage", atom},
            ?assertEqual({error, {badarg, Term}}, pack(Term, [{allow_atom, none}]))
        end},
        {"badarg too big int", ?_assertEqual(
            {error, {badarg, -16#8000000000000001}}, pack(-16#8000000000000001))
        },
        {"badarg too big uint", ?_assertEqual(
            {error, {badarg, 16#10000000000000000}}, pack(16#10000000000000000))
        },
        {"not binary",
            ?_assertEqual({error, {badarg, []}}, unpack([]))
        },
        {"empty binary unpack",
            ?_assertEqual({error, incomplete}, unpack(<<>>))
        },
        {"incomplete: unknown binary",
            ?_assertEqual({error, incomplete}, unpack(<<16#DA>>))
        }
    ].

binary_test_() ->
    [
        {"0 byte", fun() ->
            ?assertEqual({ok, <<>>}, unpack(pack(<<>>)))
        end}
    ].

old_spec_test_() ->
    Opt = [{spec, old}],
    [
        {"old spec", [
            ?_assertEqual(<<161,1>>, pack(<<1>>, Opt)),
            ?_assertEqual(<<162,1,2>>, pack(<<1,2>>, Opt)),
            ?_assertMatch(<<191, _:31/binary >>, pack(binary_a(31), Opt)),
            ?_assertMatch(<<218, 0, 32, _:32/binary >>, pack(binary_a(32), Opt)),
            ?_assertMatch(<<218, 255, 255, _:65535/binary >>, pack(binary_a(65535), Opt)),
            ?_assertMatch(<<219, 0, 1, 0, 0, _:65536/binary >>, pack(binary_a(65536), Opt))
        ]}
    ].

new_spec_string_test_() ->
    Opts = [{spec, new}],
    AsBinOpts = [{string, as_binary} | Opts],
    Bin256 = binary_a(256),
    Str256 = dup(256, $a),
    Bin65536 = binary_a(65536),
    Str65536 = dup(65536, $a),
    [
        {"pack_str binary as_list", [[
            ?_assertEqual(<<16#C4, 3, 97,97,97>>, pack(binary_a(3), [{string, As} | Opts])),
            ?_assertMatch(<<16#C4, 255, _:255/binary>>, pack(binary_a(255), [{string, As} | Opts])),
            ?_assertMatch(<<16#C5, 1, 0, _:256/binary>>, pack(Bin256, [{string, As} | Opts])),
            ?_assertMatch(<<16#C5, 255,255, _:65535/binary>>, pack(binary_a(65535), [{string, As} | Opts])),
            ?_assertMatch(<<16#C6, 0, 1, 0, 0, _:65536/binary>>, pack(Bin65536, [{string, As} | Opts]))
            ] || As <- [as_list]
        ]},
        {"pack_str binary as_binary", [
            ?_assertMatch(<<2#101:3, 31:5, _:31/binary>>, pack(binary_a(31), AsBinOpts)),
            ?_assertMatch(<<16#D9,32,_:32/binary>>, pack(binary_a(32), AsBinOpts)),
            ?_assertMatch(<<16#D9,255,_:255/binary>>, pack(binary_a(255), AsBinOpts)),
            ?_assertMatch(<<16#DA,1,0,_:256/binary>>, pack(Bin256, AsBinOpts)),
            ?_assertMatch(<<16#DA,255,255,_:65535/binary>>, pack(binary_a(65535), AsBinOpts)),
            ?_assertMatch(<<16#DB,0,1,0,0,_:65536/binary>>, pack(Bin65536, AsBinOpts))
        ]},
        {"pack_str string as_list, as_binary", [
            ?_assertEqual(<<2#101:3, 3:5, "aaa">>, pack("aaa", [{string, as_list} | Opts])),
            ?_assertMatch(<<16#D9, 32, _:32/binary>>, pack(dup(32, $a), [{string, as_list} | Opts])),
            ?_assertMatch(<<16#DA, 1, 0, _:256/binary>>, pack(Str256, [{string, as_list} | Opts])),
            ?_assertMatch(<<16#DB, 0, 1, 0, 0, _:65536/binary>>, pack(Str65536, [{string, as_list} | Opts]))
        ]},
        {"pack_str string as_binary => array of int", [[
            ?_assertEqual(<<2#1001:4, 3:4, "aaa">>, pack("aaa", [{string, As} | Opts])),
            ?_assertMatch(<<16#DC, 1, 0, _:256/binary>>, pack(Str256, [{string, As} | Opts])),
            ?_assertMatch(<<16#DD, 0, 1, 0, 0, _:65536/binary>>, pack(Str65536, [{string, As} | Opts]))
            ] || As <- [as_binary]
        ]},
        {"pack_str list as_list, as_binary", [[
            %% 1001XXXX, up to 15 elements
            ?_assertEqual(<<2#1001:4, 3:4, 255,255,255>>, pack(dup(3, -1), [{string, PackStr} | Opts])),
            %% 0xDC, two bytes, N objects
            ?_assertMatch(<<16#DC, 1, 0, _:256/binary>>, pack(dup(256, -1), [{string, PackStr} | Opts])),
            %% 0xDD, four bytes, N objects
            ?_assertMatch(<<16#DD, 0, 1, 0, 0, _:65536/binary>>, pack(dup(65536, -1), [{string, PackStr} | Opts]))
            ] || PackStr <- [as_list, as_binary]
        ]},
        {"unpack_str bin as_binary, as_list", [[
            ?_assertEqual({ok, <<"aaa">>}, unpack(<<16#C4, 3, "aaa">>, [{string, As} | Opts])),
            ?_assertEqual({ok, Bin256}, unpack(<<16#C5, 1,0, Bin256/binary>>, [{string, As} | Opts])),
            ?_assertEqual({ok, Bin65536}, unpack(<<16#C6, 0,1,0,0, Bin65536/binary>>, [{string, As} | Opts]))
            ] ||  As <- [as_binary, as_list]
        ]},
        {"unpack_str str as_binary, as_list", [[
            ?_assertEqual({ok, str(As, <<"aaa">>)}, unpack(<<2#101:3, 3:5, 97,97,97>>, [{string, As} | Opts])),
            ?_assertEqual({ok, str(As, binary_a(32))}, unpack(<<16#D9, 32, (binary_a(32))/binary>>, [{string, As} | Opts])),
            ?_assertEqual({ok, str(As, Bin256)}, unpack(<<16#DA, 1,0, Bin256/binary>>, [{string, As} | Opts])),
            ?_assertEqual({ok, str(As, Bin65536)}, unpack(<<16#DB, 0,1,0,0, Bin65536/binary>>, [{string, As} | Opts]))
            ] || As <- [as_binary, as_list]
        ]}
    ].

str_validation_test_() ->
    String = unicode:characters_to_binary("абвгдеёжзийклмнопрстуфхцчшщъыьэюя"),
    N = 16,
    InvalidStr = binary:copy(<<255>>, N),
    WrongPack = <<16#D9, N:8, InvalidStr/binary>>,
    Opts = [{spec, new}, {string, as_binary}],
    NoValidation = [{validate_string, false} | Opts],
    DoValidation = [{validate_string, true} | Opts],
    Packed = pack(String, Opts),
    [
        {"validate_string false, on unpacking", [
            ?_assertEqual({ok, String}, unpack(Packed, NoValidation)),
            ?_assertEqual({ok, InvalidStr}, unpack(WrongPack, NoValidation))
        ]},
        {"validate_string true, on unpacking", [
            ?_assertEqual({ok, String}, unpack(Packed, DoValidation)),
            ?_assertEqual({error, {invalid_string, InvalidStr}}, unpack(WrongPack, DoValidation))
        ]}
    ].

enable_str_test() ->
    ?assertEqual(<<2#101:3, 7:5,  "saitama">>, pack(<<"saitama">>, [{spec, old}])),
    %% binary becomes str8 as_binary
    ?assertEqual(<<2#101:3, 7:5, "saitama">>, pack(<<"saitama">>, [{spec, new}, {string, as_binary}])).

%%

test_incomplete(Len, Term, OrigBin, Len) ->
    ?assertEqual({ok, Term}, unpack(OrigBin));
test_incomplete(I, Term, OrigBin, Len) when I < Len ->
    <<Bin:I/binary, _/binary>> = OrigBin,
    ?assertEqual({error, incomplete}, unpack(Bin)),
    test_incomplete(I + 1, Term, OrigBin, Len).

incomplete_test() ->
    Term = test_utils:test_data(),
    Bin = pack(Term),
    test_incomplete(0, Term, Bin, byte_size(Bin)).

test_continue(Term, <<_:8>> = Bin, State) ->
    ?assertEqual({Term, <<>>}, msgpack:decode_continue(Bin, State));
test_continue(Term, <<Bin:1/binary, Rest/binary>>, State0) ->
    {continue, State} = msgpack:decode_continue(Bin, State0),
    test_continue(Term, Rest, State).

continue_test() ->
    Term = test_utils:test_data(),
    {continue, State} = msgpack:decode_start(<<>>, []),
    test_continue(Term, pack(Term), State).

unpack_stream_test() ->
    Term = test_utils:test_data(),
    Bin = binary:copy(pack(Term), 3),
    {Term, Rem0} = msgpack:unpack_stream(Bin),
    {Term, Rem1} = msgpack:unpack_stream(Rem0),
    {Term, <<>>} = msgpack:unpack_stream(Rem1),
    ok.

%%-- internals ----------------------------------------------------------------

dup(Len, S) ->
    lists:duplicate(Len, S).

binary_a(Len) ->
    binary:copy(<<$a>>, Len).
