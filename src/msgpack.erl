-module(msgpack).

%% API
-export([
    pack/1,
    pack/2,
    unpack/1,
    unpack/2,
    unpack_stream/1,
    unpack_stream/2
]).

%% API experimantal
-export([
    decode_start/2,
    decode_continue/2
]).

-include("msgpack.hrl").

-export_type([
    msgpack_term/0,
    msgpack_map/0,
    map_type/0,
    options/0,
    string_method/0,
    state/0
]).

%% Types

-type msgpack_term() :: [msgpack_term()] | msgpack_map() |
    integer() | float() | boolean() | binary() | string() | atom().
-type msgpack_map_jsx() :: [{msgpack_term(), msgpack_term()}] | [{}].
-type msgpack_map() :: msgpack_map_jsx() | map().
-type map_type() :: jsx | map.
-type string_method() :: as_binary | as_list.

-type options() :: [
    {spec, new | old} |
    {allow_atom, none | pack | [atom()]} |
    {string, string_method()} |
    {validate_string, boolean()} |
    {map_format, map_type()}
].

-type opt_record() :: #options{}.
-export_type([
    opt_record/0
]).

-type state() :: msgpack_decoder:state().

%%-- API Implementation -------------------------------------------------------

-spec pack(msgpack_term()) -> binary() | {error, any()}.
pack(Term) ->
    pack(Term, []).

-spec pack(msgpack_term(), options()) -> binary() | {error, any()}.
pack(Term, Opts) ->
    Option = parse_options(Opts),
    try
        msgpack_packer:pack(Term, Option)
    catch
        throw:Exception ->
            {error, Exception}
    end.

-spec unpack(binary()) -> {ok, msgpack_term()}
                        | {error, not_just_binary} % a term deserilized, but binary remains
                        | {error, incomplete}      % too few binary to deserialize complete binary
                        | {error, {badarg, term()}}.
unpack(Bin) ->
    unpack(Bin, []).

-spec unpack(binary(), options()) -> {ok, msgpack_term()} | {error, any()}.
unpack(Bin, Opts) ->
    case unpack_stream(Bin, Opts) of
        {error, _} = E ->
            E;
        {Term, <<>>} ->
            {ok, Term};
        {_, Binary} when is_binary(Binary) andalso byte_size(Binary) > 0 ->
            {error, not_just_binary}
    end.

-spec unpack_stream(binary()) ->
    {msgpack_term(), binary()} | {error, incomplete} | {error, {badarg, term()}} | {error, any()}.
unpack_stream(Bin) ->
    unpack_stream(Bin, []).

-spec unpack_stream(binary(), options()) ->
    {msgpack_term(), binary()} | {error, incomplete} | {error, {badarg, term()}} | {error, any()}.
unpack_stream(Bin, Opts0) when is_binary(Bin) ->
    Opts = parse_options(Opts0),
    try
        msgpack_unpacker:unpack(Bin, Opts)
    catch
        throw:Exception ->
            {error, Exception}
    end;
unpack_stream(Other, _) ->
    {error, {badarg, Other}}.

%%

-spec decode_start(binary(), options()) ->
    {msgpack_term(), binary()} | {continue, state()} | {error, any()}.
decode_start(Bin, Opts) ->
    msgpack_decoder:decode_start(Bin, parse_options(Opts)).

-spec decode_continue(binary(), state()) ->
    {msgpack_term(), binary()} | {continue, state()} | {error, any()}.
decode_continue(Bin, State) ->
    msgpack_decoder:decode_continue(Bin, State).

%%-- internals ----------------------------------------------------------------

-spec parse_options(options()) -> opt_record().
parse_options(Opt) ->
    parse_options(Opt, #options{}).

%%

-spec parse_options(options(), opt_record()) -> opt_record().
parse_options([], Opt) ->
    Opt;

parse_options([{spec, Spec} | T], Opt) when Spec =:= new orelse Spec =:= old ->
    parse_options(T, Opt#options{spec = Spec});

parse_options([{allow_atom, Type} | T], Opt) when Type =:= none orelse Type =:= pack ->
    parse_options(T, Opt#options{allow_atom = Type});

parse_options([{allow_atom, []} | T], Opt) ->
    parse_options(T, Opt#options{allow_atom = none});

parse_options([{allow_atom, Atoms0} | T], Opt) when is_list(Atoms0) ->
    Atoms = lists:flatten([[A, erlang:atom_to_binary(A, utf8)] || A <- Atoms0, is_atom(A)]),
    parse_options(T, Opt#options{allow_atom = Atoms});

parse_options([{string, As} | T], Opt) when As =:= as_binary orelse As =:= as_list ->
    parse_options(T, Opt#options{string = As});

parse_options([{validate_string, Bool} | T], Opt) when is_boolean(Bool) ->
    parse_options(T, Opt#options{validate_string = Bool});

parse_options([{map_format, Type} | T], Opt) when Type =:= jsx; Type =:= map ->
    parse_options(T, Opt#options{map_format = Type}).
