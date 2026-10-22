-module(msgpack_decoder).

-include("msgpack.hrl").

%% API
-export([
    decode_start/2,
    decode_continue/2
]).

-export_type([
    state/0
]).

-record(state, {
    stack :: [value_type()] | {value, msgpack:msgpack_term()},
    options :: msgpack:opt_record(),
    buffer :: binary()
}).

-type state() :: #state{}.
-type bit_size() :: 32 | 64.
-type value() :: {msgpack:msgpack_term(), binary()}.
-type value_type() ::
    incomplete |
    {uint | int | float, bit_size()} |
    {raw | string, pos_integer()} |
    {array, pos_integer(), list()} |
    {map, pos_integer(), msgpack:msgpack_map() | {msgpack:msgpack_term(), msgpack:msgpack_map()}}.
-type expected() :: {wait, [value_type()], binary()}.
-type result() :: value() | expected().
-type decoder() :: fun((binary(), msgpack:opt_record()) -> result()).

%%-- API Implementation -------------------------------------------------------

-spec decode_start(binary(), msgpack:opt_record()) ->
    value() | {continue, state()} | {error, any()}.
decode_start(Bin, Opts) ->
    decode_with(Bin, fun decode/2, Opts).

-spec decode_continue(binary(), state()) ->
    value() | {continue, state()} | {error, any()}.
decode_continue(Bin, #state{stack = {value, Term}}) ->
    {Term, Bin};
decode_continue(Bin, State = #state{stack = [Top | Stack], buffer = Buff, options = Opts}) ->
    Decoder = get_decoder(Top),
    case decode_with(<<Buff/binary, Bin/binary>>, Decoder, Opts) of
        {error, _} = Err ->
            Err;
        {continue, #state{stack = Term} = S} ->
            {continue, S#state{
                stack = Term ++ Stack
            }};
        {Term, Rest} ->
            StateUpd = State#state{
                stack = update_stack(Term, Stack),
                buffer = <<>>
            },
            decode_continue(Rest, StateUpd)
    end.

%%-- internals ----------------------------------------------------------------

-spec decode_with(binary(), decoder(), msgpack:opt_record()) ->
    value() | {continue, state()} | {error, any()}.
decode_with(Bin, Decoder, Opts) ->
    try Decoder(Bin, Opts) of
        {wait, Term, Rest} ->
            {continue, #state{
                stack = Term,
                options = Opts,
                buffer = Rest
            }};
        Else ->
            Else
    catch
        throw:Exception ->
            {error, Exception}
    end.

%%

-spec decode(binary(), msgpack:opt_record()) -> result().

decode(<<16#C0, Rest/binary>>, _) ->
    {null, Rest};
decode(<<16#C2, Rest/binary>>, _) ->
    {false, Rest};
decode(<<16#C3, Rest/binary>>, _) ->
    {true, Rest};

%% unsigned integer
decode(<<16#CC, V:8/unsigned, Rest/binary>>, _) ->
    {V, Rest};
decode(<<16#CD, V:16/big-unsigned, Rest/binary>>, _) ->
    {V, Rest};
decode(<<16#CE, Rest/binary>>, Opts) ->
    decode_uint(32, Rest, Opts);
decode(<<16#CF, Rest/binary>>, Opts) ->
    decode_uint(64, Rest, Opts);

%% signed integers
decode(<<16#D0, V:8/signed, Rest/binary>>, _) ->
    {V, Rest};
decode(<<16#D1, V:16/big-signed, Rest/binary>>, _) ->
    {V, Rest};
decode(<<16#D2, Rest/binary>>, Opts) ->
    decode_int(32, Rest, Opts);
decode(<<16#D3, Rest/binary>>, Opts) ->
    decode_int(64, Rest, Opts);

%% float
decode(<<16#CA, Rest/binary>>, Opts) ->
    decode_float(32, Rest, Opts);
decode(<<16#CB, Rest/binary>>, Opts) ->
    decode_float(64, Rest, Opts);

%% new spec: raw bytes
decode(<<16#C4, L:8, Rest/binary>>, Opts = #options{spec = new}) ->
    decode_raw(L, Rest, Opts);
decode(<<16#C5, L:16/big-unsigned, Rest/binary>>, Opts = #options{spec = new}) ->
    decode_raw(L, Rest, Opts);
decode(<<16#C6, L:32/big-unsigned, Rest/binary>>, Opts = #options{spec = new}) ->
    decode_raw(L, Rest, Opts);

%% old spec: raw bytes
decode(<<2#101:3, L:5, Rest/binary>>, Opts = #options{spec = old}) ->
    decode_raw(L, Rest, Opts);

%% new spec: string
decode(<<2#101:3, L:5, Rest/binary>>, Opts = #options{spec = new}) ->
    decode_string(L, Rest, Opts);

%% new spec 
decode(<<16#D9, L:8, Rest/binary>>, Opts = #options{spec = new}) ->
    decode_string(L, Rest, Opts);

%% new spec: string
%% old spec: binary
decode(<<16#DA, L:16/big-unsigned, Rest/binary>>, Opts) ->
    case Opts#options.spec of
        old ->
            decode_raw(L, Rest, Opts);
        new ->
            decode_string(L, Rest, Opts)
    end;
decode(<<16#DB, L:32/big-unsigned, Rest/binary>>, Opts) ->
    case Opts#options.spec of
        old ->
            decode_raw(L, Rest, Opts);
        new ->
            decode_string(L, Rest, Opts)
    end;

%% array
decode(<<2#1001:4, L:4, Rest/binary>>, Opt) ->
    decode_array(Rest, L, [], Opt);
decode(<<16#DC, L:16/big-unsigned, Rest/binary>>, Opt) ->
    decode_array(Rest, L, [], Opt);
decode(<<16#DD, L:32/big-unsigned, Rest/binary>>, Opt) ->
    decode_array(Rest, L, [], Opt);

%% map
decode(<<2#1000:4, L:4, Rest/binary>>, Opts = #options{map_format = Fmt}) ->
    {Decoder, New} = map_decoder(Fmt),
    Decoder(Rest, L, New, Opts);
decode(<<16#DE, L:16/big-unsigned, Rest/binary>>, Opts = #options{map_format = Fmt}) ->
    {Decoder, New} = map_decoder(Fmt),
    Decoder(Rest, L, New, Opts);
decode(<<16#DF, L:32/big-unsigned, Rest/binary>>, Opts = #options{map_format = Fmt}) ->
    {Decoder, New} = map_decoder(Fmt),
    Decoder(Rest, L, New, Opts);

%% positive int
decode(<<0:1, V:7, Rest/binary>>, _) ->
    {V, Rest};

%% negative int
decode(<<2#111:3, V:5, Rest/binary>>, _) ->
    {V - 2#100000, Rest};

%% unused
decode(<<16#C1, _R/binary>>, _) ->
    throw({badarg, 16#C1});

decode(<<Bin/binary>>, _) ->
    {wait, [incomplete], Bin}.

%%

-spec decode_uint(bit_size(), binary(), msgpack:opt_record()) -> result().
decode_uint(N, Bin, _) ->
    case Bin of
        <<V:N/big-unsigned, Rest/binary>> ->
            {V, Rest};
        _ ->
            {wait, [{uint, N}], Bin}
    end.

-spec decode_int(bit_size(), binary(), msgpack:opt_record()) -> result().
decode_int(N, Bin, _) ->
    case Bin of
        <<V:N/big-signed, Rest/binary>> ->
            {V, Rest};
        _ ->
            {wait, [{int, N}], Bin}
    end.

-spec decode_float(bit_size(), binary(), msgpack:opt_record()) -> result().
decode_float(N, Bin, _) ->
    case Bin of
        <<V:N/big-float, Rest/binary>> ->
            {V, Rest};
        <<0:1, 16#FF:8, 0:23, Rest/binary>> ->
            {positive_infinity, Rest};
        <<0:1, 2#11111111111:11, 0:52, Rest/binary>> ->
            {positive_infinity, Rest};
        <<1:1, 16#FF:8, 0:23, Rest/binary>> ->
            {negative_infinity, Rest};
        <<1:1, 2#11111111111:11, 0:52, Rest/binary>> ->
            {negative_infinity, Rest};
        <<_:1, 16#FF:8, _:23, Rest/binary>> ->
            {nan, Rest};
        <<_:1, 2#11111111111:11, _:52, Rest/binary>> ->
            {nan, Rest};
        _ ->
            {wait, [{float, N}], Bin}
     end.

-spec decode_raw(pos_integer(), binary(), msgpack:opt_record()) -> result().
decode_raw(L, Bin, Opts) ->
    case Bin of
        <<V:L/binary, Rest/binary>> ->
            {msgpack_utils:maybe_atom(V, Opts), Rest};
        _ ->
            {wait, [{raw, L}], Bin}
    end.

-spec decode_string(pos_integer(), binary(), msgpack:opt_record()) -> result().
decode_string(L, Bin, #options{string = Meth, validate_string = Validate}) ->
    case Bin of
        <<V:L/binary, Rest/binary>> ->
            {msgpack_utils:string_as(Meth, V, Validate), Rest};
        _ ->
            {wait, [{string, L}], Bin}
    end.

-spec decode_array(binary(), non_neg_integer(), list(), msgpack:opt_record()) -> result().
decode_array(Bin, 0, Acc, _) ->
    {lists:reverse(Acc), Bin};
decode_array(<<>> = Bin, L, Acc, _) ->
    {wait, [{array, L, Acc}], Bin};
decode_array(<<Bin/binary>>, L, Acc, Opt) ->
    case decode(Bin, Opt) of
        {Term, Rest} ->
            decode_array(Rest, L - 1, [Term | Acc], Opt);
        {wait, Wait, Rest} ->
            {wait, Wait ++ [{array, L, Acc}], Rest}
    end.

-spec decode_map(binary(), non_neg_integer(), map(), msgpack:opt_record()) -> result(). 
decode_map(Bin, 0, Map, _) ->
    {Map, Bin};
decode_map(<<>> = Bin, L, Map, _) when is_map(Map) ->
    {wait, [{map, L, Map}], Bin};
decode_map(Bin, L, Map, Opts) when is_map(Map) ->
    case decode(Bin, Opts) of
        {Key, Rest} ->
            case decode(Rest, Opts) of
                {Value, Rest2} ->
                    decode_map(Rest2, L - 1, Map#{Key => Value}, Opts);
                {wait, Wait, Rest3} ->
                    {wait, Wait ++ [{map, L, {Key, Map}}], Rest3}
            end;
        {wait, Wait, Rest} ->
            {wait, Wait ++ [{map, L, Map}], Rest}
    end;
decode_map(Bin, L, {Key, Map}, Opts) ->
    case decode(Bin, Opts) of
        {Value, Rest} ->
            decode_map(Rest, L - 1, Map#{Key => Value}, Opts);
        {wait, Wait, Rest} ->
            {wait, Wait ++ [{map, L, {Key, Map}}], Rest}
    end;
decode_map(Bin, L, {K, V, Map}, Opts) ->
    decode_map(Bin, L - 1, Map#{K => V}, Opts).

-spec decode_jsx(binary(), non_neg_integer(), proplists:proplist(), msgpack:opt_record()) -> result().
decode_jsx(Bin, 0, [], _) ->
    {[{}], Bin};
decode_jsx(Bin, 0, Map, _) ->
    {lists:reverse(Map), Bin};
decode_jsx(<<>> = Bin, L, Map, _) when is_list(Map) ->
    {wait, [{map, L, Map}], Bin};
decode_jsx(Bin, L, Map, Opts) when is_list(Map) ->
    case decode(Bin, Opts) of
        {Key, Rest} ->
            case decode(Rest, Opts) of
                {Value, Rest2} ->
                    decode_jsx(Rest2, L - 1, [{Key, Value} | Map], Opts);
                {wait, Wait, Rest3} ->
                    {wait, Wait ++ [{map, L, {Key, Map}}], Rest3}
            end;
        {wait, Wait, Rest} ->
            {wait, Wait ++ [{map, L, Map}], Rest}
    end;
decode_jsx(Bin, L, {Key, Map}, Opts) ->
    case decode(Bin, Opts) of
        {Value, Rest} ->
            decode_jsx(Rest, L - 1, [{Key, Value} | Map], Opts);
        {wait, Wait, Rest} ->
            {wait, Wait ++ [{map, L, Map}], Rest}
    end;
decode_jsx(Bin, L, {K, V, Map}, Opts) ->
    decode_jsx(Bin, L - 1, [{K, V} | Map], Opts).

%%

-spec get_decoder(value_type()) -> decoder().
get_decoder(incomplete) ->
    fun decode/2;
get_decoder({uint, N}) ->
    fun (Bin, Opts) ->
        decode_uint(N, Bin, Opts)
    end;
get_decoder({int, N}) ->
    fun (Bin, Opts) ->
        decode_int(N, Bin, Opts)
    end;
get_decoder({float, N}) ->
    fun (Bin, Opts) ->
        decode_float(N, Bin, Opts)
    end;
get_decoder({raw, L}) ->
    fun (Bin, Opts) ->
        decode_raw(L, Bin, Opts)
    end;
get_decoder({string, L}) ->
    fun (Bin, Opts) ->
        decode_string(L, Bin, Opts)
    end;
get_decoder({array, L, Arr}) ->
    fun (Bin, Opts) ->
        decode_array(Bin, L, Arr, Opts)
    end;
get_decoder({map, L, Map}) ->
    fun
        (Bin, Opts = #options{map_format = map}) ->
            decode_map(Bin, L, Map, Opts);
        (Bin, Opts = #options{map_format = jsx}) ->
            decode_jsx(Bin, L, Map, Opts)
    end.

-spec update_stack(msgpack:msgpack_term(), [value_type()]) -> [value_type()].
update_stack(Term, [{array, L, Arr} | Stack]) ->
    [{array, L - 1, [Term | Arr]} | Stack];
update_stack(Term, [{map, L, {Key, Map}} | Stack]) ->
    [{map, L, {Key, Term, Map}} | Stack];
update_stack(Term, [{map, L, Map} | Stack]) ->
    [{map, L, {Term, Map}} | Stack];
update_stack(Term, []) ->
    {value, Term}.

%%

map_decoder(map) ->
    {fun decode_map/4, maps:new()};
map_decoder(jsx) ->
    {fun decode_jsx/4, []}.
