-module(msgpack_unpacker).

-export([
    unpack/2
]).

-include("msgpack.hrl").

-type options() :: msgpack:opt_record().

%%-- API Implementation -------------------------------------------------------

-spec unpack(binary(), options()) -> {msgpack:msgpack_term(), binary()} | {error, any()} | no_return().

%% atom
unpack(<<16#C0, Rest/binary>>, _) ->
    {null, Rest};
unpack(<<16#C2, Rest/binary>>, _) ->
    {false, Rest};
unpack(<<16#C3, Rest/binary>>, _) ->
    {true, Rest};

%% unsigned integer
unpack(<<16#CC, V:8/unsigned, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#CD, V:16/big-unsigned, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#CE, V:32/big-unsigned, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#CF, V:64/big-unsigned, Rest/binary>>, _) ->
    {V, Rest};

%% signed integer
unpack(<<16#D0, V:8/signed, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#D1, V:16/big-signed, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#D2, V:32/big-signed, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#D3, V:64/big-signed, Rest/binary>>, _) ->
    {V, Rest};

%% float
unpack(<<16#CA, V:32/float, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#CA, 0:1, 16#FF:8, 0:23, Rest/binary>>, _) ->
    {positive_infinity, Rest};
unpack(<<16#CA, 1:1, 16#FF:8, 0:23, Rest/binary>>, _) ->
    {negative_infinity, Rest};
unpack(<<16#CA, _:1, 16#FF:8, _:23, Rest/binary>>, _) ->
    {nan, Rest};
unpack(<<16#CB, V:64/big-float, Rest/binary>>, _) ->
    {V, Rest};
unpack(<<16#CB, 0:1, 2#11111111111:11, 0:52, Rest/binary>>, _) ->
    {positive_infinity, Rest};
unpack(<<16#CB, 1:1, 2#11111111111:11, 0:52, Rest/binary>>, _) ->
    {negative_infinity, Rest};
unpack(<<16#CB, _:1, 2#11111111111:11, _:52, Rest/binary>>, _) ->
    {nan, Rest};

%% new spec: raw bytes
unpack(<<16#C4, L:8/unsigned, V:L/binary, Rest/binary>>, Opt) ->
    {msgpack_utils:maybe_atom(V, Opt), Rest};
unpack(<<16#C5, L:16/big-unsigned, V:L/binary, Rest/binary>>, Opt) ->
    {msgpack_utils:maybe_atom(V, Opt), Rest};
unpack(<<16#C6, L:32/big-unsigned, V:L/binary, Rest/binary>>, Opt) ->
    {msgpack_utils:maybe_atom(V, Opt), Rest};

%% new spec: string
%% old spec: raw bytes
unpack(<<2#101:3, L:5, V:L/binary, Rest/binary>>, Opt) ->
    {str_or_raw(V, Opt), Rest};

%% D9 is only for new spec
unpack(<<16#D9, L:8, V:L/binary, Rest/binary>>, #options{spec = new} = Opt) ->
    {msgpack_utils:string_as(Opt#options.string, V, Opt#options.validate_string), Rest};

%% DA and DB, are string/binary
unpack(<<16#DA, L:16/big-unsigned, V:L/binary, Rest/binary>>, Opt) ->
    {str_or_raw(V, Opt), Rest};

unpack(<<16#DB, L:32/big-unsigned, V:L/binary, Rest/binary>>, Opt) ->
    {str_or_raw(V, Opt), Rest};

%% arrays
unpack(<<2#1001:4, L:4, Rest/binary>>, Opt) ->
    unpack_array(Rest, L, [], Opt);
unpack(<<16#DC, L:16/big-unsigned, Rest/binary>>, Opt) ->
    unpack_array(Rest, L, [], Opt);
unpack(<<16#DD, L:32/big-unsigned, Rest/binary>>, Opt) ->
    unpack_array(Rest, L, [], Opt);

%% maps
unpack(<<2#1000:4, L:4, Rest/binary>>, Opt) ->
    Unpacker = map_unpacker(Opt#options.map_format),
    Unpacker(Rest, L, Opt);
unpack(<<16#DE, L:16/big-unsigned, Rest/binary>>, Opt) ->
    Unpacker = map_unpacker(Opt#options.map_format),
    Unpacker(Rest, L, Opt);

unpack(<<16#DF, L:32/big-unsigned, Rest/binary>>, Opt) ->
    Unpacker = map_unpacker(Opt#options.map_format),
    Unpacker(Rest, L, Opt);

%% positive int
unpack(<<0:1, V:7, Rest/binary>>, _) ->
    {V, Rest};

%% negative int
unpack(<<2#111:3, V:5, Rest/binary>>, _) ->
    {V - 2#100000, Rest};

%% reserved
unpack(<<16#C1, _R/binary>>, _) ->
    throw({badarg, 16#C1});

unpack(<<_Bin/binary>>, _Opt) ->
    throw(incomplete).

%%-- internals ----------------------------------------------------------------

-spec unpack_array(binary(), non_neg_integer(), [msgpack:msgpack_term()], options()) ->
    {[msgpack:msgpack_term()], binary()} | no_return().
unpack_array(<<Bin/binary>>, 0, Acc, _) ->
    {lists:reverse(Acc), Bin};
unpack_array(<<Bin/binary>>, Len, Acc, Opt) ->
    {Term, Rest} = unpack(Bin, Opt),
    unpack_array(Rest, Len - 1, [Term | Acc], Opt).

%%

map_unpacker(map) ->
    fun unpack_map/3;
map_unpacker(jsx) ->
    fun unpack_map_jsx/3.

-spec unpack_map(binary(), non_neg_integer(), options()) ->
    {map(), binary()} | no_return().
unpack_map(Bin, Len, Opt) ->
    unpack_map(Bin, Len, maps:new(), Opt).

-spec unpack_map_jsx(binary(), non_neg_integer(), options()) ->
    {proplists:proplist(), binary()} | no_return().
unpack_map_jsx(Bin, Len, Opt) ->
    unpack_map_jsx(Bin, Len, [], Opt).

-spec unpack_map(binary(), non_neg_integer(), map(), options()) ->
    {map(), binary()} | no_return().
unpack_map(<<Bin/binary>>, 0, Map, _) ->
    {Map, Bin};
unpack_map(<<Bin/binary>>, L, Map, Opt) ->
    {Key, Rest} = unpack(Bin, Opt),
    {Value, Rest2} = unpack(Rest, Opt),
    unpack_map(Rest2, L - 1, Map#{Key => Value}, Opt).

-spec unpack_map_jsx(binary(), non_neg_integer(), proplists:proplist(), options()) ->
    {proplists:proplist(), binary()} | no_return().
unpack_map_jsx(<<Bin/binary>>, 0, [], _) ->
    {[{}], Bin};
unpack_map_jsx(<<Bin/binary>>, 0, Map, _) ->
    {lists:reverse(Map), Bin};
unpack_map_jsx(<<Bin/binary>>, Len, Map, Opt) ->
    {Key, Rest} = unpack(Bin, Opt),
    {Value, Rest2} = unpack(Rest, Opt),
    unpack_map_jsx(Rest2, Len - 1, [{Key, Value} | Map], Opt).

%%

-spec str_or_raw(binary(), options()) -> binary() | atom() | string().
str_or_raw(V, #options{spec = old} = Opt) ->
    msgpack_utils:maybe_atom(V, Opt);
str_or_raw(V, #options{spec = new, string = Meth, validate_string = Validate}) ->
    msgpack_utils:string_as(Meth, V, Validate).
