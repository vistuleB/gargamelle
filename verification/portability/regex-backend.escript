#!/usr/bin/env escript
main([Package, Root, Inputs]) ->
    lists:foreach(fun(Path) -> true = code:add_patha(Path) end,
                  filelib:wildcard(filename:join([Root, "build", "dev", "erlang", "*", "ebin"]))),
    true = code:add_patha(filename:join(Package, "ebin")),
    {ok, Json} = file:read_file(Inputs),
    Cases = json:decode(Json),
    Ports = length(erlang:ports()),
    {message_queue_len, Messages} = process_info(self(), message_queue_len),
    {Micros, Results} = timer:tc(fun() -> [check(C) || C <- Cases] end),
    Failures = failures(Package),
    true = Ports =:= length(erlang:ports()),
    {message_queue_len, Messages} = process_info(self(), message_queue_len),
    io:put_chars(json:encode(#{cases => Results, failures => Failures,
                              microseconds => Micros, ports_restored => true,
                              mailbox_restored => true})).

check(#{<<"pattern">> := Pattern, <<"text">> := Text}) ->
    case gargamelle_regex:pattern_valid(Pattern) of
        false -> #{valid => false};
        true -> #{valid => true, matched => gargamelle_regex:pattern_matches(Pattern, Text)}
    end.

raised(Run) ->
    try Run(), false catch error:_ -> true end.

failures(Package) ->
    true = raised(fun() -> gargamelle_regex:pattern_matches(<<"[">>, <<>>) end),
    Text = <<(binary:copy(<<"a">>, 32))/binary, "!">>,
    true = raised(fun() -> gargamelle_regex:pattern_matches(<<"(a+)+$">>, Text) end),
    true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
    {ok, Probe} = gargamelle:pattern(gargamelle:text(), <<"a">>),
    Conditional = gargamelle:if_then(gargamelle:text(), Probe, gargamelle:text()),
    Exclusion = gargamelle:exclude(gargamelle:text(), Probe),
    {ok, Membership} = gargamelle:contains(gargamelle:array(gargamelle:text()), Probe, 1, none),
    {ok, Keys} = gargamelle:property_names(gargamelle:dictionary(gargamelle:text()), Probe),
    {ok, Input} = gargamelle:parse(<<"\"a\"">>),
    {ok, Array} = gargamelle:parse(<<"[\"a\"]">>),
    {ok, Object} = gargamelle:parse(<<"{\"a\":\"a\"}">>),
    Executable = filename:join([Package, "build", "native", "gargamelle_regex_port"]),
    Saved = Executable ++ ".saved",
    ok = file:rename(Executable, Saved),
    try
        true = raised(fun() -> gargamelle_regex:pattern_valid(<<"a">>) end),
        true = raised(fun() -> gargamelle:validate(Conditional, Input) end),
        true = raised(fun() -> gargamelle:validate(Exclusion, Input) end),
        true = raised(fun() -> gargamelle:validate(Membership, Array) end),
        true = raised(fun() -> gargamelle:validate(Keys, Object) end),
        true = raised(fun() -> gargamelle:defaulted(gargamelle:record(fun(V) -> V end),
                                                  <<"value">>, Probe, Input) end),
        %% A native executable failure must not terminate its calling process.
        ok = file:write_file(Executable, <<"#!/bin/sh\nexit 7\n">>),
        ok = file:change_mode(Executable, 8#755),
        true = raised(fun() -> gargamelle_regex:pattern_valid(<<"a">>) end),
        %% A no-match reply is invalid for a syntax-only request, not bad syntax.
        ok = file:write_file(Executable, <<"#!/bin/sh\nprintf '\\000\\000\\000\\001\\001'\n">>),
        true = raised(fun() -> gargamelle_regex:pattern_valid(<<"a">>) end)
    after
        file:delete(Executable),
        ok = file:rename(Saved, Executable)
    end,
    true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
    #{invalid_match_raises => true, resource_raises => true, missing_helper_raises => true,
      native_exit_raises => true, protocol_raises => true,
      auxiliary_failures_escape => true, recovery => true}.
