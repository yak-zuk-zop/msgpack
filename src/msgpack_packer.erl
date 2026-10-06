-module(msgpack_packer).

%% API
-export([
    pack/2
]).

-include("msgpack.hrl").

-type options() :: msgpack:opt_record().

%%-- API Implementation -------------------------------------------------------

-spec pack(msgpack:msgpack_term(), options()) -> binary().

pack(I, _) when is_integer(I) andalso I < 0 ->
    pack_int(I);
pack(I, _) when is_integer(I) ->
    pack_uint(I);
pack(F, _) when is_float(F) ->
    <<16#CB:8, F:64/big-float>>;
pack(null, _Opt) ->
    <<16#C0:8>>;
pack(false, _) ->
    <<16#C2:8>>;
pack(true, _) ->
    <<16#C3:8>>;

pack(Bin, Opt) when is_binary(Bin) ->
    pack_binary(Bin, Opt);

pack(Atom, #options{allow_atom = pack} = Opt) when is_atom(Atom) ->
    pack_binary(erlang:atom_to_binary(Atom, utf8), Opt);
pack(Atom, #options{allow_atom = Known = [_ | _]} = Opt) when is_atom(Atom) ->
    case lists:member(Atom, Known) of
        true ->
            pack_binary(erlang:atom_to_binary(Atom, utf8), Opt);
        false ->
            throw({badarg, Atom})
    end;

pack([{}], Opt = #options{map_format = jsx}) ->
    pack_map([], Opt);
pack([{_,_} | _] = Map, Opt = #options{map_format = jsx}) ->
    pack_map(Map, Opt);
pack(Map, Opt) when is_map(Map) ->
    pack_map(maps:to_list(Map), Opt);

pack(List, #options{spec = new, string = as_list} = Opt)  when is_list(List) ->
    try
        case lists:all(fun is_integer/1, List) of
            true ->
                case pack_string(List, Opt) of
                    %% NOTE: due to erlang string format, msgpack can't
                    %% tell the difference between string and list of
                    %% integers. Thus users have to take care not to
                    %% include invalid unicode characters.
                    %% Here to fallback into list(int()).
                    {error, _} ->
                        pack_array(List, Opt);
                    Bin when is_binary(Bin) ->
                        Bin
                end;
            false ->
                pack_array(List, Opt)
        end
    catch error:badarg ->
        pack_array(List, Opt)
    end;

pack(List, Opt)  when is_list(List) ->
    pack_array(List, Opt);

pack(Other, _Opt) ->
    throw({badarg, Other}).

%%-- internals ----------------------------------------------------------------

%% negative fixnum
-spec pack_int(integer()) -> binary() | no_return().
pack_int(N) when N >= -32->
    <<2#111:3, N:5>>;
%% int 8
pack_int(N) when N >= -128 ->
    <<16#D0:8, N:8>>;
%% int 16
pack_int(N) when N >= -16#8000 ->
    <<16#D1:8, N:16/big-signed-integer>>;
%% int 32
pack_int(N) when N >= -16#80000000 ->
    <<16#D2:8, N:32/big-signed-integer>>;
%% int 64
pack_int(N) when N >= -16#8000000000000000 ->
    <<16#D3:8, N:64/big-signed-integer>>;
%% too big int
pack_int(N) ->
    throw({badarg, N}).

%% positive fixnum
-spec pack_uint(non_neg_integer()) -> binary() | no_return().
pack_uint(N) when N < 128 ->
    <<2#0:1, N:7>>;
%% uint 8
pack_uint(N) when (N band 16#FF) =:= N ->
    <<16#CC:8, N:8>>;
%% uint 16
pack_uint(N) when (N band 16#FFFF) =:= N ->
    <<16#CD:8, N:16/big-unsigned-integer>>;
%% uint 32
pack_uint(N) when (N band 16#FFFFFFFF) =:= N->
    <<16#CE:8, N:32/big-unsigned-integer>>;
%% uint 64
pack_uint(N) when (N band 16#FFFFFFFFFFFFFFFF) =:= N ->
    <<16#CF:8, N:64/big-unsigned-integer>>;
%% too big unit
pack_uint(N) ->
    throw({badarg, N}).

-spec pack_binary(binary(), options()) -> binary() | no_return().
pack_binary(Bin, #options{spec = old}) ->
    pack_raw(Bin);
pack_binary(Bin, #options{spec = new, string = as_list}) ->
    pack_raw_new(Bin);
pack_binary(Bin, #options{spec = new, string = as_binary} = Opt) ->
    pack_string(unicode:characters_to_list(Bin), Opt);
pack_binary(Bin, #options{spec = new}) ->
    pack_raw_new(Bin).

%% @doc raw bytes in old spec
-spec pack_raw(binary()) -> binary() | no_return().
pack_raw(Bin) ->
    case byte_size(Bin) of
        Len when Len < 32 ->
            <<2#101:3, Len:5, Bin/binary>>;
        Len when Len < 16#10000 -> % 65536
            <<16#DA:8, Len:16/big-unsigned-integer, Bin/binary>>;
        Len when Len < 16#100000000 ->
            <<16#DB:8, Len:32/big-unsigned-integer, Bin/binary>>;
        _ ->
            throw({badarg, Bin})
    end.

%% raw bytes in new spec
-spec pack_raw_new(binary()) -> binary() | no_return().
pack_raw_new(Bin) ->
    case byte_size(Bin) of
        Len when Len < 256 ->
            <<16#C4:8, Len:8, Bin/binary>>;
        Len when Len < 16#10000 -> % 65536
            <<16#C5:8, Len:16/big-unsigned-integer, Bin/binary>>;
        Len when Len < 16#100000000 ->
            <<16#C6:8, Len:32/big-unsigned-integer, Bin/binary>>;
        _ ->
            throw({badarg, Bin})
    end.

%% @doc String MAY be unicode. Or may be EUC-JP, SJIS, UTF-1024 or anything.
%% EVERY implementation must show its binary length just after type indicator
%% to skip the damn string if its unreadable.
-spec pack_string(string(), options()) -> binary() | {error, atom()}.
pack_string(String, _Opt) ->
    case unicode:characters_to_binary(String) of
        {error, _Bin, _} ->
            {error, broken_unicode};
        {incomplete, _Bin, _} ->
            {error, incomplete_unicode};
        Bin ->
            case byte_size(Bin) of
                Len when Len < 32 ->
                    <<2#101:3, Len:5, Bin/binary>>;
                Len when Len < 256 ->
                    <<16#D9:8, Len:8, Bin/binary>>;
                Len when Len < 16#10000 -> % 65536
                    <<16#DA:8, Len:16/big-unsigned-integer, Bin/binary>>;
                Len when Len < 16#100000000 ->
                    <<16#DB:8, Len:32/big-unsigned-integer, Bin/binary>>;
                _ ->
                    throw({badarg, String})
            end
    end.

%%

-spec pack_array([msgpack:msgpack_term()], options()) -> binary() | no_return().
pack_array([], _) ->
    <<2#1001:4, 0:4>>;
pack_array([A], Opt) ->
    <<2#1001:4, 1:4, (pack(A, Opt))/binary>>;
pack_array([A, B], Opt) ->
    <<2#1001:4, 2:4, (pack(A, Opt))/binary, (pack(B, Opt))/binary>>;
pack_array([A, B, C], Opt) ->
    <<2#1001:4, 3:4, (pack(A, Opt))/binary, (pack(B, Opt))/binary, (pack(C, Opt))/binary>>;
pack_array([A, B, C, D], Opt) ->
    <<2#1001:4, 4:4, (pack(A, Opt))/binary, (pack(B, Opt))/binary, (pack(C, Opt))/binary,
        (pack(D, Opt))/binary>>;
pack_array([A, B, C, D, E], Opt) ->
    <<2#1001:4, 5:4, (pack(A, Opt))/binary, (pack(B, Opt))/binary, (pack(C, Opt))/binary,
        (pack(D, Opt))/binary, (pack(E, Opt))/binary>>;
pack_array(L, Opt) ->
    Payload = << <<(pack(E, Opt))/binary>> || E <- L >>,
    case length(L) of
        Len when Len < 16 ->
            <<2#1001:4, Len:4, Payload/binary>>;
        Len when Len < 16#10000 ->
            <<16#DC:8, Len:16/big-unsigned-integer, Payload/binary>>;
        Len when Len < 16#100000000 ->
            <<16#DD:8, Len:32/big-unsigned-integer, Payload/binary>>;
        _ ->
            throw({badarg, L})
    end.

%%

-spec pack_map(msgpack:msgpack_map(), options()) -> binary() | no_return().
pack_map([], _Opt) ->
    <<2#1000:4, 0:4>>;

pack_map([{Ka, Va}], Opt) ->
    <<2#1000:4, 1:4, (pack(Ka, Opt))/binary, (pack(Va, Opt))/binary>>;

pack_map([{Ka, Va}, {Kb, Vb}], Opt) ->
    <<2#1000:4, 2:4,
       (pack(Ka, Opt))/binary, (pack(Va, Opt))/binary,
       (pack(Kb, Opt))/binary, (pack(Vb, Opt))/binary>>;

pack_map([{Ka, Va}, {Kb, Vb}, {Kc, Vc}], Opt) ->
    <<2#1000:4, 3:4,
       (pack(Ka, Opt))/binary, (pack(Va, Opt))/binary,
       (pack(Kb, Opt))/binary, (pack(Vb, Opt))/binary,
       (pack(Kc, Opt))/binary, (pack(Vc, Opt))/binary>>;

pack_map([{Ka, Va}, {Kb, Vb}, {Kc, Vc}, {Kd, Vd}], Opt) ->
    <<2#1000:4, 4:4,
       (pack(Ka, Opt))/binary, (pack(Va, Opt))/binary,
       (pack(Kb, Opt))/binary, (pack(Vb, Opt))/binary,
       (pack(Kc, Opt))/binary, (pack(Vc, Opt))/binary,
       (pack(Kd, Opt))/binary, (pack(Vd, Opt))/binary>>;

pack_map(M, Opt) ->
    Payload = << <<(pack(K, Opt))/binary, (pack(V, Opt))/binary>> || {K, V} <- M >>,
    case length(M) of
        Len when Len < 16 ->
            <<2#1000:4, Len:4, Payload/binary>>;
        Len when Len < 16#10000 -> % 65536
            <<16#DE:8, Len:16/big-unsigned-integer, Payload/binary>>;
        Len when Len < 16#100000000->
            <<16#DF:8, Len:32/big-unsigned-integer, Payload/binary>>;
        _ ->
            throw({badarg, M})
    end.
