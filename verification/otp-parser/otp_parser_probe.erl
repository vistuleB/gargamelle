-module(otp_parser_probe).
-export([adapted/1, hybrid/1, default/1, snapshot/1, callback_failures/0]).

%% Investigation only. No production parser or public API is modified.
adapted(Source) ->
    Decoders = #{integer => fun number/1, float => fun number/1,
        object_start => fun(_) -> {#{}, []} end,
        object_push => fun push/3, object_finish => fun finish/2},
    try json:decode(Source, ok, Decoders) of
        {Value, ok, Rest} ->
            case whitespace(Rest) of
                <<>> ->
                    case nonfinite(Value) of
                        true -> {error, nonfinite_number};
                        false -> {ok, Value}
                    end;
                _ -> {error, syntax}
            end
    catch
        error:unexpected_end -> {error, syntax};
        error:{invalid_byte, _} -> {error, syntax};
        error:{unexpected_sequence, _} -> {error, syntax}
    end.

number(Token) ->
    case gargamelle_runtime:parse_number(Token) of
        {ok, Number} -> Number;
        {error, nonfinite_number} -> gargamelle_nonfinite_number
    end.
push(Key, Value, {Map, Keys}) ->
    NextKeys = case maps:is_key(Key, Map) of true -> Keys; false -> [Key | Keys] end,
    {maps:put(Key, Value, Map), NextKeys}.
finish({Map, Keys}, Parent) -> {{gargamelle_object, lists:reverse(Keys), Map}, Parent}.
whitespace(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 -> whitespace(Rest);
whitespace(Rest) -> Rest.
nonfinite(gargamelle_nonfinite_number) -> true;
nonfinite({gargamelle_object, _, Map}) -> lists:any(fun nonfinite/1, maps:values(Map));
nonfinite(Values) when is_list(Values) -> lists:any(fun nonfinite/1, Values);
nonfinite(_) -> false.

%% Conservative guard deliberately permits false positives inside strings and
%% negative fractions: it performs no second custom token scanner.
hybrid(Source) ->
    case binary:match(Source, <<"-0">>) of
        nomatch ->
            case adapted(Source) of
                {error, syntax} -> {fallback_syntax, gargamelle_runtime:parse_scalar_json(Source, ordered)};
                Result -> {otp, Result}
            end;
        _ -> {fallback_zero, gargamelle_runtime:parse_scalar_json(Source, ordered)}
    end.

default(Source) ->
    try {ok, json:decode(Source)}
    catch
        error:unexpected_end -> {error, syntax};
        error:{invalid_byte, _} -> {error, syntax};
        error:{unexpected_sequence, _} -> {error, syntax}
    end.

%% Snapshot binary64 bits and object first-insertion order, rather than hiding
%% differences behind canonical serialization. Integer nodes remain distinguishable.
snapshot({error, Reason}) -> #{error => atom_to_binary(Reason)};
snapshot({ok, Value}) -> #{value => value_snapshot(Value)}.
value_snapshot(null) -> #{type => <<"null">>};
value_snapshot(Value) when is_boolean(Value) -> #{type => <<"boolean">>, value => Value};
value_snapshot(Value) when is_binary(Value) -> #{type => <<"string">>, value => Value};
value_snapshot(Value) when is_float(Value) ->
    <<Bits:64/unsigned>> = <<Value:64/float>>,
    #{type => <<"number">>, bits => integer_to_binary(Bits)};
value_snapshot(Value) when is_integer(Value) -> #{type => <<"integer">>, value => integer_to_binary(Value)};
value_snapshot({gargamelle_object, Keys, Map}) ->
    #{type => <<"object">>, entries => [[Key, value_snapshot(maps:get(Key, Map))] || Key <- Keys]};
value_snapshot(Value) when is_map(Value) ->
    #{type => <<"object">>, entries => [[Key, value_snapshot(Item)] || {Key, Item} <- maps:to_list(Value)]};
value_snapshot(Value) when is_list(Value) -> #{type => <<"array">>, values => [value_snapshot(Item) || Item <- Value]}.

callback_failures() ->
    maps:from_list([{Kind, failure(Kind, Source)} || {Kind, Source} <-
        [{integer, <<"1">>}, {float, <<"1.25">>}]]).
failure(Kind, Source) ->
    try json:decode(Source, ok, #{Kind => fun(_) -> error(probe_callback_failure) end}) of
        _ -> <<"unexpected_success">>
    catch error:probe_callback_failure -> <<"operational_exception_preserved">>;
        error:{unexpected_sequence, _} -> <<"reclassified_as_syntax">>
    end.
