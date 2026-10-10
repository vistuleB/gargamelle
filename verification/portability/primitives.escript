#!/usr/bin/env escript
%% Request/response primitive runner. It does not call the JavaScript decoder.
main(_) ->
    {ok, gargamelle_runtime, Beam} = compile:file(
        "src/gargamelle_runtime.erl", [binary, warnings_as_errors]),
    {module, gargamelle_runtime} = code:load_binary(gargamelle_runtime, "probe", Beam),
    loop().
loop() ->
    case io:get_line(standard_io, "") of
        eof -> ok;
        Line ->
            Request = json:decode(unicode:characters_to_binary(Line)),
            Reply = case Request of
                #{<<"cells">> := true} ->
                    {ok, reference_cells, CellBeam} = compile:file(
                        "verification/portability/reference_cells.erl",
                        [binary, warnings_as_errors]),
                    {module, reference_cells} = code:load_binary(
                        reference_cells, "probe", CellBeam),
                    reference_cells:selftest();
                #{<<"pattern">> := Pattern, <<"text">> := Text} ->
                    case re:compile(Pattern, [unicode]) of
                        {error, _} -> #{valid => false};
                        {ok, RE} ->
                            case re:run(Text, RE, [{capture, none}]) of
                                match -> #{valid => true, matched => true};
                                nomatch -> #{valid => true, matched => false};
                                {error, Reason} -> erlang:error({regex_failure, Reason})
                            end
                    end;
                #{<<"source">> := Source} ->
                    case gargamelle_runtime:canonical_scalar_json(Source) of
                        {ok, Text} ->
                            case gargamelle_runtime:parse_scalar_json(Source) of
                                {ok, F} when is_float(F) ->
                                    <<Bits:64/unsigned>> = <<F:64/float>>,
                                    #{text => Text, bits => integer_to_binary(Bits)};
                                {ok, _} -> #{text => Text}
                            end;
                        {error, Reason} -> #{error => atom_to_binary(Reason)}
                    end;
                #{<<"strings">> := Strings} ->
                    #{sorted => gargamelle_runtime:sorted(Strings),
                      lengths => [gargamelle_runtime:codepoints(S) || S <- Strings]};
                #{<<"token">> := Token} ->
                    case gargamelle_runtime:parse_number(Token) of
                        {ok, F} ->
                            <<Bits:64/unsigned>> = <<F:64/float>>,
                            #{text => gargamelle_runtime:number_text(F),
                              bits => integer_to_binary(Bits)};
                        {error, Reason} -> #{error => atom_to_binary(Reason)}
                    end;
                #{<<"bits">> := B} ->
                    Bits = binary_to_integer(B),
                    <<F:64/float>> = <<Bits:64/unsigned>>,
                    #{text => gargamelle_runtime:number_text(F),
                      integer => gargamelle_runtime:integer(F),
                      finite => gargamelle_runtime:finite(F),
                      conversion => safe_conversion(F)}
            end,
            io:put_chars([json:encode(Reply), "\n"]),
            loop()
    end.

safe_conversion(F) ->
    case gargamelle_runtime:integer(F) andalso abs(F) =< 9007199254740991.0 of
        true ->
            Int = gargamelle_runtime:as_int(F),
            #{integer_text => gargamelle_runtime:int_text(Int),
              float_text => gargamelle_runtime:number_text(
                  gargamelle_runtime:as_float(Int))};
        false -> null
    end.
