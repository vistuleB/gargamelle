-module(gargamelle_runtime).
-export([integer/1, finite/1, as_int/1, as_float/1, int_text/1,
         parse_number/1, number_text/1, sorted/1, codepoints/1,
         parse_scalar_json/1, canonical_scalar_json/1, fresh_identity/0,
         with_construction/1, with_context/2, with_walk/1, recursive_cell/2,
         identity_tracker/2, recursion_guard/2, parse/7, canonical/1]).

canonical(Source) ->
    {ok, Text} = canonical_scalar_json(Source), Text.

parse(Source, Null, Bool, Number, String, Array, Object) ->
    case parse_scalar_json(Source) of
        {ok, Value} -> {ok, admitted_value(Value, {Null, Bool, Number, String, Array, Object})};
        {error, syntax} -> {error, {admission_error, <<"syntax">>}};
        {error, nonfinite_number} -> {error, {admission_error, <<"non-finite number">>}};
        {error, non_scalar_string} -> {error, {admission_error, <<"non-scalar string">>}}
    end.
admitted_value(null, {Make, _, _, _, _, _}) -> Make();
admitted_value(B, {_, Make, _, _, _, _}) when is_boolean(B) -> Make(B);
admitted_value(N, {_, _, Make, _, _, _}) when is_float(N) -> Make(N);
admitted_value(S, {_, _, _, Make, _, _}) when is_binary(S) -> Make(S);
admitted_value(A, {_, _, _, _, Make, _} = Factories) when is_list(A) ->
    Make([admitted_value(V, Factories) || V <- A]);
admitted_value(O, {_, _, _, _, _, Make} = Factories) when is_map(O) ->
    Make([{K, admitted_value(V, Factories)} || {K, V} <- maps:to_list(O)]).

%% Portability primitives and scalar-domain experiments. This module is not a
%% complete Erlang backend; admission, scalar strings, numeric and graph externals
%% are attached along with canonical emission; ECMAScript regex remains gated.
integer(X) when is_float(X) -> X == trunc(X).
finite(X) -> is_float(X).
as_int(X) when is_float(X) -> trunc(X).
as_float(X) when is_integer(X) -> float(X).
int_text(X) when is_integer(X) -> integer_to_binary(X).

%% The admission parser must validate the JSON token syntax before calling this.
%% Convert the original decimal token, not an arbitrary-precision intermediate.
parse_number(Token) when is_binary(Token) ->
    Parts = binary:split(Token, [<<"e">>, <<"E">>]),
    [Mantissa | Exponent] = Parts,
    Decimal = case binary:match(Mantissa, <<".">>) of
        nomatch -> <<Mantissa/binary, ".0">>;
        _ -> Mantissa
    end,
    Normal = case Exponent of
        [] -> Decimal;
        [E] -> <<Decimal/binary, "e", E/binary>>
    end,
    try {ok, binary_to_float(Normal)}
    catch error:badarg -> {error, nonfinite_number}
    end.

%% Apply ECMAScript's fixed/exponential notation thresholds to OTP's shortest
%% round-trip decimal digits. Verification must establish digit-choice parity.
number_text(X) when is_float(X), X == 0.0 -> <<"0">>;
number_text(X) when is_float(X), X < 0.0 ->
    <<"-", (positive_text(-X))/binary>>;
number_text(X) when is_float(X) -> positive_text(X).

positive_text(X) ->
    Short = float_to_binary(X, [short]),
    [Mantissa | Exponent] = binary:split(Short, <<"e">>),
    E = case Exponent of [] -> 0; [EB] -> binary_to_integer(EB) end,
    [Whole, Fraction] = binary:split(Mantissa, <<".">>),
    All = <<Whole/binary, Fraction/binary>>,
    {Digits0, Leading} = drop_leading(All, 0),
    Digits = drop_trailing(Digits0),
    Point = byte_size(Whole) + E - Leading,
    Count = byte_size(Digits),
    case Point of
        P when P > 0, P =< 21, P >= Count ->
            <<Digits/binary, (zeros(P - Count))/binary>>;
        P when P > 0, P =< 21 ->
            <<Left:P/binary, Right/binary>> = Digits,
            <<Left/binary, ".", Right/binary>>;
        P when P =< 0, P > -6 ->
            <<"0.", (zeros(-P))/binary, Digits/binary>>;
        P ->
            <<First:1/binary, Rest/binary>> = Digits,
            Coefficient = case Rest of
                <<>> -> First;
                _ -> <<First/binary, ".", Rest/binary>>
            end,
            Sign = case P - 1 >= 0 of true -> <<"+">>; false -> <<>> end,
            <<Coefficient/binary, "e", Sign/binary,
              (integer_to_binary(P - 1))/binary>>
    end.

drop_leading(<<"0", Rest/binary>>, N) -> drop_leading(Rest, N + 1);
drop_leading(Bin, N) -> {Bin, N}.
drop_trailing(Bin) ->
    case binary:last(Bin) of
        $0 -> drop_trailing(binary:part(Bin, 0, byte_size(Bin) - 1));
        _ -> Bin
    end.
zeros(N) -> binary:copy(<<"0">>, N).

%% Unicode-scalar primitives for the authorized 0.2.0 admission domain.
sorted(Values) ->
    [Value || {_, Value} <- lists:keysort(1, [{utf16(V), V} || V <- Values])].
utf16(Value) ->
    case unicode:characters_to_binary(Value, utf8, {utf16, big}) of
        Binary when is_binary(Binary) -> Binary;
        _ -> erlang:error(invalid_unicode_string)
    end.
codepoints(Value) -> count_codepoints(Value, 0).
count_codepoints(<<>>, Count) -> Count;
count_codepoints(<<_/utf8, Rest/binary>>, Count) ->
    count_codepoints(Rest, Count + 1).

%% Unicode-scalar admission scanner. Syntax and duplicate resolution finish
%% before domain checking; private invalid units never become public Strings.
parse_scalar_json(Source) ->
    try read_value(whitespace(Source)) of
        {Value, Rest} ->
            case whitespace(Rest) of
                <<>> ->
                    case {has_nonfinite(Value), has_non_scalar(Value)} of
                        {true, _} -> {error, nonfinite_number};
                        {_, true} -> {error, non_scalar_string};
                        _ -> {ok, Value}
                    end;
                _ -> {error, syntax}
            end
    catch throw:gargamelle_json_syntax -> {error, syntax}
    end.
whitespace(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 ->
    whitespace(Rest);
whitespace(Rest) -> Rest.
syntax() -> throw(gargamelle_json_syntax).

read_value(<<"null", Rest/binary>>) -> {null, Rest};
read_value(<<"true", Rest/binary>>) -> {true, Rest};
read_value(<<"false", Rest/binary>>) -> {false, Rest};
read_value(<<$", _/binary>> = Source) -> read_string(Source);
read_value(<<$[, Rest/binary>>) -> read_array(whitespace(Rest), []);
read_value(<<${, Rest/binary>>) -> read_object(whitespace(Rest), #{});
read_value(<<First, _/binary>> = Source) when First == $-;
                                           First >= $0, First =< $9 ->
    read_number(Source);
read_value(_) -> syntax().

read_array(<<$], Rest/binary>>, []) -> {[], Rest};
read_array(Source, Acc) ->
    {Value, Rest} = read_value(Source),
    case whitespace(Rest) of
        <<$], Tail/binary>> -> {lists:reverse([Value | Acc]), Tail};
        <<$,, Tail/binary>> -> read_array_item(whitespace(Tail), [Value | Acc]);
        _ -> syntax()
    end.
read_array_item(<<$], _/binary>>, _) -> syntax();
read_array_item(Source, Acc) -> read_array(Source, Acc).

read_object(<<$}, Rest/binary>>, Map) when map_size(Map) == 0 -> {Map, Rest};
read_object(<<$", _/binary>> = Source, Map) ->
    {Key, Rest} = read_string(Source),
    case whitespace(Rest) of
        <<$:, ValueSource/binary>> ->
            {Value, Tail} = read_value(whitespace(ValueSource)),
            Next = maps:put(Key, Value, Map),
            case whitespace(Tail) of
                <<$}, End/binary>> -> {Next, End};
                <<$,, More/binary>> -> read_object_item(whitespace(More), Next);
                _ -> syntax()
            end;
        _ -> syntax()
    end;
read_object(_, _) -> syntax().
read_object_item(<<$}, _/binary>>, _) -> syntax();
read_object_item(Source, Map) -> read_object(Source, Map).

%% Preserve unpaired surrogate units privately as WTF-8 until final-domain
%% checking. They never become public Gleam Strings. This lets duplicate-key
%% replacement discard an invalid value before admission, just like overflow.
read_string(<<$", Rest/binary>>) -> read_chars(Rest, []).
read_chars(<<$", Rest/binary>>, Acc) -> {iolist_to_binary(lists:reverse(Acc)), Rest};
read_chars(<<$\\, $u, A, B, C, D, Rest/binary>>, Acc) ->
    Unit = (hex(A) bsl 12) bor (hex(B) bsl 8) bor (hex(C) bsl 4) bor hex(D),
    case {Unit, Rest} of
        {High, <<$\\, $u, E, F, G, H, Tail/binary>>} when High >= 16#d800, High =< 16#dbff ->
            Low = (hex(E) bsl 12) bor (hex(F) bsl 8) bor (hex(G) bsl 4) bor hex(H),
            case Low >= 16#dc00 andalso Low =< 16#dfff of
                true ->
                    Scalar = 16#10000 + ((High - 16#d800) bsl 10) + Low - 16#dc00,
                    read_chars(Tail, [<<Scalar/utf8>> | Acc]);
                false -> read_chars(Rest, [string_unit(High) | Acc])
            end;
        _ -> read_chars(Rest, [string_unit(Unit) | Acc])
    end;
read_chars(<<$\\, Escape, Rest/binary>>, Acc) ->
    Character = case Escape of
        $" -> $"; $\\ -> $\\; $/ -> $/;
        $b -> 8; $f -> 12; $n -> 10; $r -> 13; $t -> 9;
        _ -> syntax()
    end,
    read_chars(Rest, [Character | Acc]);
read_chars(<<Character, Rest/binary>>, Acc) when Character >= 32 ->
    read_chars(Rest, [Character | Acc]);
read_chars(_, _) -> syntax().
hex(C) when C >= $0, C =< $9 -> C - $0;
hex(C) when C >= $a, C =< $f -> C - $a + 10;
hex(C) when C >= $A, C =< $F -> C - $A + 10;
hex(_) -> syntax().
string_unit(Unit) when Unit >= 16#d800, Unit =< 16#dfff ->
    <<(16#e0 bor (Unit bsr 12)), (16#80 bor ((Unit bsr 6) band 63)),
      (16#80 bor (Unit band 63))>>;
string_unit(Unit) -> <<Unit/utf8>>.

read_number(Source) ->
    Length = number_end(Source, 0),
    <<Token:Length/binary, Rest/binary>> = Source,
    case re:run(Token,
        <<"^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$">>,
        [{capture, none}]) of
        match ->
            Value = case parse_number(Token) of
                {ok, Float} -> Float;
                {error, nonfinite_number} -> gargamelle_nonfinite_number
            end,
            {Value, Rest};
        nomatch -> syntax()
    end.
number_end(<<C, Rest/binary>>, Length) when C == $-; C == $+; C == $.;
    C == $e; C == $E; C >= $0, C =< $9 -> number_end(Rest, Length + 1);
number_end(_, Length) -> Length.

has_nonfinite(gargamelle_nonfinite_number) -> true;
has_nonfinite(Value) when is_list(Value) -> lists:any(fun has_nonfinite/1, Value);
has_nonfinite(Value) when is_map(Value) ->
    lists:any(fun has_nonfinite/1, maps:values(Value));
has_nonfinite(_) -> false.

has_non_scalar(Value) when is_binary(Value) ->
    case unicode:characters_to_binary(Value, utf8, utf8) of
        B when is_binary(B) -> false;
        _ -> true
    end;
has_non_scalar(Value) when is_list(Value) -> lists:any(fun has_non_scalar/1, Value);
has_non_scalar(Value) when is_map(Value) ->
    lists:any(fun has_non_scalar/1, maps:keys(Value)) orelse
    lists:any(fun has_non_scalar/1, maps:values(Value));
has_non_scalar(_) -> false.

canonical_scalar_json(Source) ->
    case parse_scalar_json(Source) of
        {ok, Value} -> {ok, iolist_to_binary(encode_scalar(Value))};
        Error -> Error
    end.
encode_scalar(null) -> <<"null">>;
encode_scalar(true) -> <<"true">>;
encode_scalar(false) -> <<"false">>;
encode_scalar(Value) when is_float(Value) -> number_text(Value);
encode_scalar(Value) when is_binary(Value) -> quote_string(Value);
encode_scalar(Value) when is_list(Value) ->
    [$[, join([encode_scalar(V) || V <- Value]), $]];
encode_scalar(Value) when is_map(Value) ->
    Keys = [Key || {_, Key} <- lists:keysort(1,
        [{enumeration_key(K), K} || K <- maps:keys(Value)])],
    [${, join([[quote_string(K), $:, encode_scalar(maps:get(K, Value))]
               || K <- Keys]), $}].
join([]) -> [];
join([First | Rest]) -> [First | [[$,, V] || V <- Rest]].
enumeration_key(<<"0">>) -> {0, 0};
enumeration_key(<<First, _/binary>> = Key) when First >= $1, First =< $9,
                                               byte_size(Key) =< 10 ->
    case index_digits(Key) of
        true ->
            Index = binary_to_integer(Key),
            case Index < 4294967295 of
                true -> {0, Index};
                false -> {1, utf16(Key)}
            end;
        false -> {1, utf16(Key)}
    end;
enumeration_key(Key) -> {1, utf16(Key)}.
index_digits(<<>>) -> true;
index_digits(<<C, Rest/binary>>) when C >= $0, C =< $9 -> index_digits(Rest);
index_digits(_) -> false.

quote_string(Value) -> [$", escape_string(Value, []), $"].
escape_string(<<>>, Acc) -> lists:reverse(Acc);
escape_string(<<C, Rest/binary>>, Acc) ->
    Escaped = case C of
        $" -> <<"\\\"">>;
        $\\ -> <<"\\\\">>;
        8 -> <<"\\b">>;
        9 -> <<"\\t">>;
        10 -> <<"\\n">>;
        12 -> <<"\\f">>;
        13 -> <<"\\r">>;
        _ when C < 32 ->
            <<"\\u00", (hex_digit(C bsr 4)), (hex_digit(C band 15))>>;
        _ -> C
    end,
    escape_string(Rest, [Escaped | Acc]).
hex_digit(N) when N < 10 -> $0 + N;
hex_digit(N) -> $a + N - 10.

%% Construction registries are frozen into private ContextNode wrappers. Walk
%% registries are temporary. Both scopes restore previous state on every exit.
-define(CELLS, '$gargamelle_cells').
-define(WALK, '$gargamelle_walk').
fresh_identity() -> make_ref().
with_construction(Build) -> scoped(?CELLS, #{}, fun() ->
    Value = Build(), {Value, get(?CELLS)}
end).
with_context(Context, Run) -> scoped(?CELLS, Context, Run).
with_walk(Run) -> scoped(?WALK, #{}, Run).
scoped(Key, Value, Run) ->
    Previous = get(Key),
    put(Key, Value),
    try Run()
    after
        case Previous of
            undefined -> erase(Key);
            _ -> put(Key, Previous)
        end
    end.
recursive_cell(Make, Missing) ->
    Key = make_ref(),
    cell_set(Key, unbound),
    Read = fun() -> case cell_state(Key) of
        {bound, Value} -> {ok, Value};
        _ -> {error, Missing}
    end end,
    Bind = fun(Value) -> case cell_state(Key) of
        unbound -> cell_set(Key, {bound, Value});
        _ -> error(recursive_cell_already_finalized)
    end end,
    Reject = fun() -> cell_set(Key, rejected) end,
    Make(Read, Bind, Reject).
cell_state(Key) -> case get(?CELLS) of
    Context when is_map(Context) -> maps:get(Key, Context, unavailable);
    _ -> unavailable
end.
cell_set(Key, Value) -> case get(?CELLS) of
    Context when is_map(Context) -> put(?CELLS, maps:put(Key, Value, Context)), nil;
    _ -> error(no_construction_context)
end.
identity_tracker(Make, Identity) ->
    Key = make_ref(),
    walk_set(Key, #{}),
    Make(fun(Node) ->
        Id = Identity(Node),
        Seen = walk_get(Key),
        Before = maps:is_key(Id, Seen),
        walk_set(Key, maps:put(Id, true, Seen)),
        Before
    end).
recursion_guard(Make, Identity) ->
    Key = make_ref(),
    walk_set(Key, #{}),
    Make(fun(Node) ->
        Id = Identity(Node),
        State = walk_get(Key),
        case maps:get(Id, State, unseen) of
            active -> 1;
            complete -> 2;
            unseen -> walk_set(Key, maps:put(Id, active, State)), 0
        end
    end, fun(Node) ->
        walk_set(Key, maps:put(Identity(Node), complete, walk_get(Key))), nil
    end).
walk_get(Key) -> maps:get(Key, get(?WALK)).
walk_set(Key, Value) -> put(?WALK, maps:put(Key, Value, get(?WALK))), nil.
