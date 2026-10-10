#!/usr/bin/env escript
main([Package, Root, Inputs]) ->
    lists:foreach(fun(Path) -> true = code:add_patha(Path) end,
                  filelib:wildcard(filename:join([Root, "build", "dev", "erlang", "*", "ebin"]))),
    true = code:add_patha(filename:join(Package, "ebin")),
    {ok, Json} = file:read_file(Inputs),
    Cases = json:decode(Json),
    Ports = length(erlang:ports()),
    {message_queue_len, Messages} = process_info(self(), message_queue_len),
    Dictionary = lists:sort(get()),
    {trap_exit, Trapping} = process_info(self(), trap_exit),
    {Micros, Results} = timer:tc(fun() -> [check(C) || C <- Cases] end),
    Results = gargamelle_regex:with_scope(fun() -> [check(C) || C <- Cases] end),
    scoped_lifetime(Ports),
    Failures = failures(Package),
    true = Ports =:= length(erlang:ports()),
    {message_queue_len, Messages} = process_info(self(), message_queue_len),
    Dictionary = lists:sort(get()),
    {trap_exit, Trapping} = process_info(self(), trap_exit),
    io:put_chars(json:encode(#{cases => Results, failures => Failures,
                              microseconds => Micros, ports_restored => true,
                              mailbox_restored => true, scoped_cases_equal => true,
                              dictionary_restored => true, flags_restored => true})).

check(#{<<"pattern">> := Pattern, <<"text">> := Text}) ->
    case gargamelle_regex:pattern_valid(Pattern) of
        false -> #{valid => false};
        true -> #{valid => true, matched => gargamelle_regex:pattern_matches(Pattern, Text)}
    end.

raised(Run) ->
    try Run(), false catch error:_ -> true end.

scoped_lifetime(Ports) ->
    gargamelle_runtime:with_walk(fun() ->
        true = Ports =:= length(erlang:ports()), %% lazy: no port yet
        true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
        Outer = get('$gargamelle_regex_session'),
        true = Ports + 1 =:= length(erlang:ports()),
        gargamelle_regex:with_scope(fun() ->
            true = gargamelle_regex:pattern_matches(<<"b">>, <<"b">>),
            true = Ports + 2 =:= length(erlang:ports()),
            true = get('$gargamelle_regex_session') =/= Outer
        end),
        Outer = get('$gargamelle_regex_session'),
        true = Ports + 1 =:= length(erlang:ports()),
        Text = <<(binary:copy(<<"a">>, 32))/binary, "!">>,
        true = raised(fun() -> gargamelle_regex:pattern_matches(<<"(a+)+$">>, Text) end),
        true = Ports =:= length(erlang:ports()),
        true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>)
    end),
    true = Ports =:= length(erlang:ports()),
    true = raised(fun() -> gargamelle_regex:with_scope(fun() ->
        true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
        error(deliberate_scope_exception)
    end) end),
    true = Ports =:= length(erlang:ports()),
    {ok, Probe} = gargamelle:pattern(gargamelle:text(), <<"a">>),
    {ok, Input} = gargamelle:parse(<<"\"a\"">>),
    Mapped = gargamelle:map(Probe, fun(Value) ->
        true = Ports =:= length(erlang:ports()), %% closed before user conversion
        {ok, Value} = gargamelle:decode(Probe, Input),
        Value
    end),
    {ok, <<"a">>} = gargamelle:decode(Mapped, Input),
    owner_exit(false),
    true = Ports =:= length(erlang:ports()).

owner_exit(Blocked) ->
    Parent = self(),
    {Owner, OwnerMonitor} = spawn_monitor(fun() ->
        gargamelle_regex:with_scope(fun() ->
            case Blocked of
                false ->
                    true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
                    Parent ! {ready, self()},
                    receive remain_open -> ok end;
                true -> gargamelle_regex:pattern_matches(<<"a">>, <<"a">>)
            end
        end)
    end),
    case Blocked of
        false -> receive {ready, Owner} -> ok after 5000 -> error(owner_not_ready) end;
        true -> ok
    end,
    {Worker, Port} = await_worker(Owner, 200),
    WorkerMonitor = monitor(process, Worker),
    exit(Owner, kill),
    receive {'DOWN', OwnerMonitor, process, Owner, killed} -> ok after 5000 -> error(owner_exit_timeout) end,
    receive {'DOWN', WorkerMonitor, process, Worker, _} -> ok after 5000 -> error(worker_exit_timeout) end,
    undefined = erlang:port_info(Port).

await_worker(_, 0) -> error(worker_not_ready);
await_worker(Owner, Left) ->
    {dictionary, Dictionary} = process_info(Owner, dictionary),
    case proplists:get_value('$gargamelle_regex_session', Dictionary) of
        {Worker, _} ->
            case [Port || Port <- erlang:ports(), erlang:port_info(Port, connected) =:= {connected, Worker}] of
                [Port] -> {Worker, Port};
                [] -> receive after 10 -> await_worker(Owner, Left - 1) end
            end;
        _ -> receive after 10 -> await_worker(Owner, Left - 1) end
    end.

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
        true = raised(fun() -> gargamelle_regex:pattern_valid(<<"a">>) end),
        %% Owner death must close a port even while its worker awaits a response.
        ok = file:write_file(Executable, <<"#!/bin/sh\nexec cat >/dev/null\n">>),
        owner_exit(true)
    after
        file:delete(Executable),
        ok = file:rename(Saved, Executable)
    end,
    true = gargamelle_regex:pattern_matches(<<"a">>, <<"a">>),
    #{invalid_match_raises => true, resource_raises => true, missing_helper_raises => true,
      native_exit_raises => true, protocol_raises => true,
      auxiliary_failures_escape => true, owner_exit_cleanup => true, recovery => true}.
