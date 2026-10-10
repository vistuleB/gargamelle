#!/usr/bin/env escript
%% Research transport: invokes libregexp directly; no JavaScript subprocess.
main([Executable]) ->
    Port = open_port({spawn_executable, Executable}, [binary, {packet, 4}, exit_status]),
    try loop(Port) after
        try port_close(Port) catch error:badarg -> ok end
    end.
loop(Port) ->
    case io:get_line(standard_io, "") of
        eof -> ok;
        Line ->
            Request = json:decode(unicode:characters_to_binary(Line)),
            #{<<"pattern">> := Pattern, <<"text_utf16">> := Hex} = Request,
            Text = binary:decode_hex(Hex),
            Budget = maps:get(<<"budget">>, Request, 100000),
            true = port_command(Port, <<Budget:32, (byte_size(Pattern)):32,
                (byte_size(Text) div 2):32, Pattern/binary, Text/binary>>),
            Reply = receive
                {Port, {data, <<0>>}} -> #{valid => false};
                {Port, {data, <<1>>}} -> #{valid => true, matched => false};
                {Port, {data, <<2>>}} -> #{valid => true, matched => true};
                {Port, {data, <<3>>}} -> #{error => <<"operational">>};
                {Port, {exit_status, Status}} -> error({regex_port_exit, Status})
            after 5000 -> error(regex_port_timeout)
            end,
            io:put_chars([json:encode(Reply), $\n]),
            loop(Port)
    end.
