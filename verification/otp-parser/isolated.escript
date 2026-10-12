#!/usr/bin/env escript
%% One parser variant and one workload per fresh VM. No hot code replacement.
main([Build, Variant]) ->
    ok = code:add_paths(filelib:wildcard(filename:join(Build, "*/ebin"))),
    {ok, Runtime} = file:read_file("src/gargamelle_runtime.erl"),
    Reference = binary:replace(Runtime, <<"parse_scalar_json/1,">>,
        <<"parse_scalar_json/1, parse_scalar_json/2,">>),
    {ok, Probe} = file:read_file("verification/otp-parser/otp_parser_probe.erl"),
    CopyProbe = binary:replace(Probe, <<"Decoders = #{integer">>,
        <<"Decoders = #{string => fun binary:copy/1, integer">>),
    true = CopyProbe =/= Probe,
    Dir = "reports/otp-parser-isolated/",
    ok = filelib:ensure_dir(Dir ++ "placeholder"),
    ok = file:write_file(Dir ++ "otp_parser_probe.erl", CopyProbe),
    load(otp_parser_probe, Dir ++ "otp_parser_probe.erl"),
    Selected = case Variant of
        "reference" -> Reference;
        "copying_hybrid" ->
            Changed = binary:replace(Reference,
                <<"case parse_scalar_json(Source, ordered) of">>,
                <<"case element(2, otp_parser_probe:hybrid(Source)) of">>),
            true = Changed =/= Reference, Changed
    end,
    ok = file:write_file(Dir ++ "gargamelle_runtime.erl", Selected),
    load(gargamelle_runtime, Dir ++ "gargamelle_runtime.erl"),
    Request = json:decode(unicode:characters_to_binary(io:get_line(standard_io, ""))),
    Source = maps:get(<<"source">>, Request),
    Iterations = maps:get(<<"iterations">>, Request),
    Result = gargamelle:parse(Source),
    Run = fun() -> gargamelle:parse(Source) end,
    repeat(Run, 200),
    Samples = [begin erlang:garbage_collect(),
        {Before, _} = erlang:statistics(reductions),
        {Micros, Last} = timer:tc(fun() -> repeat(Run, Iterations) end),
        true = Last == Result,
        {After, _} = erlang:statistics(reductions),
        #{microseconds => Micros / Iterations, reductions => (After-Before) / Iterations}
      end || _ <- lists:seq(1, 3)],
    {Route, _} = otp_parser_probe:hybrid(Source),
    %% A small decoded field must not retain a large discarded input buffer.
    Large = iolist_to_binary([<<"{\"keep\":\"">>, binary:copy(<<"k">>,128),
        <<"\",\"discard\":\"">>, binary:copy(<<"d">>,1048576), <<"\"}">>]),
    {ok, Builder} = gargamelle:required(gargamelle:record(fun(X) -> X end),
        <<"keep">>, gargamelle:text()),
    Def = gargamelle:finish(Builder, open),
    {ok, Parsed} = gargamelle:parse(Large),
    {ok, Kept} = gargamelle:decode(Def, Parsed),
    128 = binary:referenced_byte_size(Kept),
    Reply = #{samples => Samples, route => Route,
        result_sha256 => binary:encode_hex(crypto:hash(sha256,term_to_binary(Result))),
        retained_bytes => binary:referenced_byte_size(Kept),
        runtime => list_to_binary(erlang:system_info(system_version)),
        schedulers => erlang:system_info(schedulers_online)},
    io:put_chars([json:encode(Reply), $\n]).
load(Module, Path) ->
    {ok, Module, Beam} = compile:file(Path, [binary, warnings_as_errors]),
    {module, Module} = code:load_binary(Module, Path, Beam).
repeat(Fun, 1) -> Fun();
repeat(Fun, N) -> _ = Fun(), repeat(Fun, N-1).
