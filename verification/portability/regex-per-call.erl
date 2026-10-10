-module(gargamelle_regex).
-export([pattern_valid/1, pattern_matches/2]).

%% A private worker owns one helper for one call. Native failures cannot kill
%% the caller, leave a shared service poisoned, or become validation rejection.
pattern_valid(Pattern) -> request(0, Pattern, <<>>).
pattern_matches(Pattern, Text) -> request(1, Pattern, Text).

request(Mode, Pattern, Text) ->
    Parent = self(),
    Ref = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Result = try execute(Mode, Pattern, Text)
                 catch Class:Reason -> {failure, {Class, Reason}} end,
        Parent ! {Ref, Result}
    end),
    receive
        {Ref, {success, Result}} -> demonitor(Monitor, [flush]), Result;
        {Ref, {failure, Reason}} ->
            demonitor(Monitor, [flush]), error({gargamelle_regex_failure, Reason});
        {'DOWN', Monitor, process, Pid, Reason} ->
            error({gargamelle_regex_worker_exit, Reason})
    after 6000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        receive {Ref, _} -> ok after 0 -> ok end,
        error(gargamelle_regex_worker_timeout)
    end.

execute(Mode, Pattern, Text) ->
    Utf16 = unicode:characters_to_binary(Text, utf8, {utf16, little}),
    true = is_binary(Utf16),
    Request = <<Mode:8, 100000:32, (byte_size(Pattern)):32,
                (byte_size(Utf16) div 2):32, Pattern/binary, Utf16/binary>>,
    %% Resource limits fail operationally; they are never syntax or data errors.
    case byte_size(Request) =< 16 * 1024 * 1024 of
        true -> ok;
        false -> error(gargamelle_regex_packet_limit)
    end,
    Executable = executable(),
    Port = open_port({spawn_executable, Executable},
                     [binary, {packet, 4}, exit_status]),
    try
        true = port_command(Port, Request),
        receive
            {Port, {data, <<0>>}} when Mode == 0 -> {success, false};
            {Port, {data, <<0>>}} -> error(gargamelle_regex_invalid_pattern);
            {Port, {data, <<1>>}} when Mode == 1 -> {success, false};
            {Port, {data, <<2>>}} -> {success, true};
            {Port, {data, <<3>>}} -> error(gargamelle_regex_resource_failure);
            {Port, {data, Other}} -> error({gargamelle_regex_protocol, Other});
            {Port, {exit_status, Status}} -> error({gargamelle_regex_port_exit, Status});
            {'EXIT', Port, Reason} -> error({gargamelle_regex_port_exit, Reason})
        after 5000 -> error(gargamelle_regex_port_timeout)
        end
    after
        try port_close(Port) catch error:badarg -> ok end
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
