#!/usr/bin/env escript
%% Investigation only: loads an existing, freshly compiled public Gleam module,
%% replacing its runtime dependency in memory. No shipped source is modified.
main([Build]) ->
    Paths = filelib:wildcard(filename:join(Build, "*/ebin")),
    true = code:add_paths(Paths) == ok,
    {ok, Runtime} = file:read_file("src/gargamelle_runtime.erl"),
    Reference = binary:replace(Runtime, <<"parse_scalar_json/1,">>,
        <<"parse_scalar_json/1, parse_scalar_json/2,">>),
    Hybrid = binary:replace(Reference,
        <<"case parse_scalar_json(Source, ordered) of">>,
        <<"case element(2, otp_parser_probe:hybrid(Source)) of">>),
    true = Hybrid =/= Reference,
    load(otp_parser_probe, "verification/otp-parser/otp_parser_probe.erl"),
    Keep = binary:copy(<<"k">>, 128),
    Source = iolist_to_binary([<<"{\"keep\":\"">>, Keep,
        <<"\",\"discard\":\"">>, binary:copy(<<"d">>, 1048576), <<"\"}">>]),
    {ok, Builder} = gargamelle:required(gargamelle:record(fun(X) -> X end),
        <<"keep">>, gargamelle:text()),
    Definition = gargamelle:finish(Builder, open),
    Requests = read_requests([]),
    Ref = measure_variant(Reference, Requests, Source, Definition),
    Fast = measure_variant(Hybrid, Requests, Source, Definition),
    true = maps:get(results, Ref) == maps:get(results, Fast),
    {ok, Probe} = file:read_file("verification/otp-parser/otp_parser_probe.erl"),
    CopyProbe = binary:replace(Probe, <<"Decoders = #{integer">>,
        <<"Decoders = #{string => fun binary:copy/1, integer">>),
    true = CopyProbe =/= Probe,
    CopyProbePath = "reports/otp-parser-full-path/otp_parser_probe.erl",
    ok = file:write_file(CopyProbePath, CopyProbe),
    code:purge(otp_parser_probe), code:delete(otp_parser_probe),
    load(otp_parser_probe, CopyProbePath),
    FastCopy = measure_variant(Hybrid, Requests, Source, Definition),
    true = maps:get(results, Ref) == maps:get(results, FastCopy),
    Default = maps:get(<<"keep">>, json:decode(Source)),
    {CopyValue, ok, <<>>} = json:decode(Source, ok, #{string => fun binary:copy/1}),
    Copied = maps:get(<<"keep">>, CopyValue),
    Reply = #{reference => maps:remove(results, Ref), hybrid => maps:remove(results, Fast),
        copying_hybrid => maps:remove(results, FastCopy),
        exact_public_results_match => true, source_bytes => byte_size(Source),
        default_otp_retained_string => sizes(Default),
        copying_otp_retained_string => sizes(Copied),
        runtime => list_to_binary(erlang:system_info(system_version))},
    io:put_chars([json:encode(Reply), $\n]).
read_requests(Acc) ->
    case io:get_line(standard_io, "") of
        eof -> lists:reverse(Acc);
        Line -> read_requests([json:decode(unicode:characters_to_binary(Line)) | Acc])
    end.
measure_variant(Runtime, Requests, Source, Definition) ->
    Path = "reports/otp-parser-full-path/gargamelle_runtime.erl",
    ok = filelib:ensure_dir(Path), ok = file:write_file(Path, Runtime),
    code:purge(gargamelle_runtime), code:delete(gargamelle_runtime),
    load(gargamelle_runtime, Path),
    {ok, Parsed} = gargamelle:parse(Source),
    {ok, Decoded} = gargamelle:decode(Definition, Parsed),
    #{decoded_retained_string => sizes(Decoded),
      results => [gargamelle:parse(maps:get(<<"source">>, R)) || R <- Requests],
      costs => [#{name => maps:get(<<"name">>, R),
        route => element(1, otp_parser_probe:hybrid(maps:get(<<"source">>, R))),
        samples => samples(fun() -> gargamelle:parse(maps:get(<<"source">>, R)) end,
                           maps:get(<<"iterations">>, R))} || R <- Requests]}.
sizes(Bin) -> #{bytes => byte_size(Bin), referenced_bytes => binary:referenced_byte_size(Bin)}.
load(Module, Path) ->
    {ok, Module, Beam} = compile:file(Path, [binary, warnings_as_errors]),
    {module, Module} = code:load_binary(Module, Path, Beam).
samples(Fun, N) ->
    repeat(Fun, 100),
    [begin erlang:garbage_collect(),
       {Micros, _} = timer:tc(fun() -> repeat(Fun, N) end), Micros / N
     end || _ <- lists:seq(1, 7)].
repeat(_, 0) -> ok;
repeat(Fun, N) -> _ = Fun(), repeat(Fun, N-1).
