-module(gargamelle_regex).
-export([pattern_valid/1, pattern_matches/2, with_scope/1]).

%% A lazy private worker owns one helper for one validation walk. The scope is
%% temporary process-local transport state, never retained by a definition.
%% Standalone requests receive their own scope. Nested walks restore the outer.
-define(SESSION, '$gargamelle_regex_session').
pattern_valid(Pattern) -> request(0, Pattern, <<>>).
pattern_matches(Pattern, Text) -> request(1, Pattern, Text).

with_scope(Run) ->
    Previous = get(?SESSION),
    put(?SESSION, idle),
    try Run()
    after
        try stop(get(?SESSION))
        after
            case Previous of
                undefined -> erase(?SESSION);
                _ -> put(?SESSION, Previous)
            end
        end
    end.

start() ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Owner = monitor(process, Parent),
        loop(Parent, Owner, undefined)
    end),
    put(?SESSION, {Pid, Monitor}),
    {Pid, Monitor}.

stop(idle) -> ok;
stop({Pid, Monitor}) ->
    Ref = make_ref(),
    Pid ! {stop, Ref},
    receive
        {Ref, stopped} -> demonitor(Monitor, [flush]), ok;
        {'DOWN', Monitor, process, Pid, _} -> ok
    after 1000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end
    end.

request(Mode, Pattern, Text) ->
    case get(?SESSION) of
        undefined -> with_scope(fun() -> request(Mode, Pattern, Text) end);
        idle -> request(start(), Mode, Pattern, Text);
        Session -> request(Session, Mode, Pattern, Text)
    end.

request({Pid, Monitor}, Mode, Pattern, Text) ->
    Ref = make_ref(),
    Pid ! {request, Ref, Mode, Pattern, Text},
    receive
        {Ref, {success, Result}} -> Result;
        {Ref, {failure, Reason}} ->
            error({gargamelle_regex_failure, Reason});
        {'DOWN', Monitor, process, Pid, Reason} ->
            put(?SESSION, idle),
            error({gargamelle_regex_worker_exit, Reason})
    after 6000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        receive {Ref, _} -> ok after 0 -> ok end,
        put(?SESSION, idle),
        error(gargamelle_regex_worker_timeout)
    end.

loop(Parent, Owner, Port) ->
    receive
        {request, Ref, Mode, Pattern, Text} ->
            {Next, Result} = serve(Port, Owner, Mode, Pattern, Text),
            Parent ! {Ref, Result},
            loop(Parent, Owner, Next);
        {stop, Ref} -> close(Port), Parent ! {Ref, stopped};
        {'DOWN', Owner, process, Parent, _} -> close(Port);
        {Port, {exit_status, _}} -> close(Port), loop(Parent, Owner, undefined);
        {'EXIT', Port, _} -> close(Port), loop(Parent, Owner, undefined);
        _ -> loop(Parent, Owner, Port)
    end.

serve(Port, Owner, Mode, Pattern, Text) ->
    try packet(Mode, Pattern, Text) of
        Request ->
            try ensure_port(Port) of
                Active ->
                    try execute(Active, Owner, Mode, Request) of
                        Result -> {Active, Result}
                    catch Class:Reason ->
                        close(Active), {undefined, {failure, {Class, Reason}}}
                    end
            catch Class:Reason ->
                close(Port), {undefined, {failure, {Class, Reason}}}
            end
    catch Class:Reason ->
        close(Port), {undefined, {failure, {Class, Reason}}}
    end.

ensure_port(undefined) ->
    open_port({spawn_executable, executable()}, [binary, {packet, 4}, exit_status]);
ensure_port(Port) -> Port.

close(undefined) -> ok;
close(Port) -> try port_close(Port) catch error:badarg -> ok end.

packet(Mode, Pattern, Text) ->
    Utf16 = unicode:characters_to_binary(Text, utf8, {utf16, little}),
    true = is_binary(Utf16),
    Request = <<Mode:8, 100000:32, (byte_size(Pattern)):32,
                (byte_size(Utf16) div 2):32, Pattern/binary, Utf16/binary>>,
    %% Resource limits fail operationally; they are never syntax or data errors.
    case byte_size(Request) =< 16 * 1024 * 1024 of
        true -> ok;
        false -> error(gargamelle_regex_packet_limit)
    end,
    Request.

execute(Port, Owner, Mode, Request) ->
    true = port_command(Port, Request),
    receive
        {Port, {data, <<0>>}} when Mode == 0 -> {success, false};
        {Port, {data, <<0>>}} -> error(gargamelle_regex_invalid_pattern);
        {Port, {data, <<1>>}} when Mode == 1 -> {success, false};
        {Port, {data, <<2>>}} -> {success, true};
        {Port, {data, <<3>>}} -> error(gargamelle_regex_resource_failure);
        {Port, {data, Other}} -> error({gargamelle_regex_protocol, Other});
        {Port, {exit_status, Status}} -> error({gargamelle_regex_port_exit, Status});
        {'EXIT', Port, Reason} -> error({gargamelle_regex_port_exit, Reason});
        {'DOWN', Owner, process, _, _} ->
            %% Terminate without passing owner death through failure recovery.
            close(Port), exit(self(), kill)
    after 5000 -> error(gargamelle_regex_port_timeout)
    end.

%% Release deployments may install a helper directly under priv. Development
%% builds keep binaries outside priv so Hex exports contain only portable source.
executable() ->
    Priv = code:priv_dir(gargamelle),
    Installed = filename:join(Priv, "gargamelle_regex_port"),
    case filelib:is_regular(Installed) of
        true -> Installed;
        false ->
            SourcePriv = case file:read_link(Priv) of
                {ok, Link} -> filename:absname(Link, filename:dirname(Priv));
                {error, _} -> Priv
            end,
            filename:join([SourcePriv, "..", "build", "native", "gargamelle_regex_port"])
    end.
