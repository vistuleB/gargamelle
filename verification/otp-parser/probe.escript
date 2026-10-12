#!/usr/bin/env escript
main(Args) ->
    %% Expose ordered reference mode only in an ignored temporary copy.
    {ok, Runtime} = file:read_file("src/gargamelle_runtime.erl"),
    Copy = "reports/otp-parser-reference/gargamelle_runtime.erl",
    ok = filelib:ensure_dir(Copy),
    ok = file:write_file(Copy, binary:replace(Runtime, <<"parse_scalar_json/1,">>,
        <<"parse_scalar_json/1, parse_scalar_json/2,">>)),
    ProbePath = case Args of
        [] -> "verification/otp-parser/otp_parser_probe.erl";
        ["copy"] ->
            {ok, Probe} = file:read_file("verification/otp-parser/otp_parser_probe.erl"),
            Copied = binary:replace(Probe, <<"Decoders = #{integer">>,
                <<"Decoders = #{string => fun binary:copy/1, integer">>),
            true = Copied =/= Probe,
            P = "reports/otp-parser-reference/otp_parser_probe.erl",
            ok = file:write_file(P, Copied), P
    end,
    lists:foreach(fun({Module, Path}) ->
        {ok, Module, Beam} = compile:file(Path, [binary, warnings_as_errors]),
        {module, Module} = code:load_binary(Module, Path, Beam)
    end, [{gargamelle_runtime, Copy},
          {otp_parser_probe, ProbePath}]),
    loop().
loop() ->
    case io:get_line(standard_io, "") of
        eof -> ok;
        Line ->
            Request = json:decode(unicode:characters_to_binary(Line)),
            Reply = case Request of
                #{<<"metadata">> := true} ->
                    #{beam => list_to_binary(erlang:system_info(system_version)),
                      callbacks => otp_parser_probe:callback_failures()};
                #{<<"source">> := Source} ->
                    {Route, Hybrid} = otp_parser_probe:hybrid(Source),
                    #{reference => otp_parser_probe:snapshot(gargamelle_runtime:parse_scalar_json(Source, ordered)),
                      default => otp_parser_probe:snapshot(otp_parser_probe:default(Source)),
                      adapted => otp_parser_probe:snapshot(otp_parser_probe:adapted(Source)),
                      hybrid => otp_parser_probe:snapshot(Hybrid), route => atom_to_binary(Route)};
                #{<<"benchmark">> := Source, <<"iterations">> := Iterations} ->
                    Reference = gargamelle_runtime:parse_scalar_json(Source, ordered),
                    {_, HybridResult} = otp_parser_probe:hybrid(Source),
                    true = otp_parser_probe:snapshot(Reference) == otp_parser_probe:snapshot(HybridResult),
                    #{reference => samples(fun() -> gargamelle_runtime:parse_scalar_json(Source, ordered) end, Iterations),
                      adapted => samples(fun() -> otp_parser_probe:adapted(Source) end, Iterations),
                      hybrid => samples(fun() -> otp_parser_probe:hybrid(Source) end, Iterations)}
            end,
            io:put_chars([json:encode(Reply), $\n]), loop()
    end.
samples(Fun, Iterations) ->
    repeat(Fun, 100),
    [begin erlang:garbage_collect(),
           {Before, _} = erlang:statistics(reductions),
           {Micros, _} = timer:tc(fun() -> repeat(Fun, Iterations) end),
           {After, _} = erlang:statistics(reductions),
           #{microseconds_per_parse => Micros / Iterations,
             reductions_per_parse => (After-Before) / Iterations}
     end || _ <- lists:seq(1, 7)].
repeat(_, 0) -> ok;
repeat(Fun, N) -> _ = Fun(), repeat(Fun, N-1).
