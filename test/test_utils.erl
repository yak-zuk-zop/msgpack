-module(test_utils).

%% API
-export([
    test_data/0,
    test_map/2,
    str/2
]).

%%-- API Implementation -------------------------------------------------------

test_data() ->
    [
        true, false, null,
        0, 1, 2, 123, 512, 1230, 678908, 16#FFFFFFFFFF,
        -1, -23, -512, -1230, -567898, -16#FFFFFFFFFF,
        123.123, -234.4355, 1.0e-34, 1.0e64,
        <<0, 23, 255>>,
        <<"abcABC">>, <<"абвАБВ"/utf8>>,
        [0, 42, <<"sum">>, false, [1, 2, 0.23]], [1, 42, null, [3]]
    ].

test_map(jsx, 0) ->
    [{}];
test_map(map, 0) ->
    #{};
test_map(jsx, N) ->
    [{X, X * 2} || X <- lists:seq(1, N)];
test_map(map, N) ->
    #{X => X * 2  || X <- lists:seq(1, N)}.

%%

str(as_list, S) when is_list(S) ->
    S;
str(as_binary, S) when is_list(S) ->
    list_to_binary(S);
str(as_list, S) when is_binary(S) ->
    binary_to_list(S);
str(as_binary, S) when is_binary(S) ->
    S.