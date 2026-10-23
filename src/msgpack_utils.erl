-module(msgpack_utils).

-include("msgpack.hrl").

%% API
-export([
    maybe_atom/2,
    string_as/3
]).

%%-- API Implementation -------------------------------------------------------

-spec maybe_atom(binary(), msgpack:opt_record()) -> binary() | atom().
maybe_atom(Bin, #options{allow_atom = Known = [_ | _]}) ->
    case lists:member(Bin, Known) of
        true ->
            erlang:binary_to_existing_atom(Bin, utf8);
        false ->
            binary:copy(Bin)
    end;
maybe_atom(Bin, _) ->
    binary:copy(Bin).

%%

-spec string_as(msgpack:string_method(), binary(), boolean()) -> binary() | string() | no_return().
string_as(as_binary, Bin, false) ->
    binary:copy(Bin);
string_as(as_list, Bin, false) ->
    binary_to_list(Bin);
string_as(Meth, Bin, true) ->
    CheckFun = string_check_func(Meth),
    case CheckFun(Bin) of
        {error, _S, _Rest} ->
            throw({invalid_string, Bin});
        {incomplete, _S, _Rest} ->
            throw({invalid_string, Bin});
        String ->
            String
    end.

%%-- internals ----------------------------------------------------------------

string_check_func(as_binary) ->
    fun unicode:characters_to_binary/1;
string_check_func(as_list) ->
    fun unicode:characters_to_list/1.
