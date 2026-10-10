#!/usr/bin/env escript
%% Inspect attempted surrogate encodings at the actual Erlang String boundary.
main(_) ->
    Rows = [probe(Name, Value) || {Name, Value} <- [
        {<<"scalar_astral">>, <<16#1f49c/utf8>>},
        {<<"wtf8_high_surrogate">>, <<16#ed, 16#a0, 16#80>>},
        {<<"utf16_high_surrogate">>, <<16#d800:16/little>>},
        {<<"literal_escape">>, <<"\\ud800">>}
    ]],
    io:put_chars([json:encode(Rows), $\n]).
probe(Name, Value) ->
    #{name => Name, bytes => binary:encode_hex(Value),
      utf8 => attempt(fun() ->
          case unicode:characters_to_binary(Value, utf8, utf8) of
              B when is_binary(B) -> <<"valid">>;
              _ -> <<"invalid">>
          end
      end),
      gleam_string_length => attempt(fun() -> string:length(Value) end),
      gleam_string_lowercase => attempt(fun() ->
          binary:encode_hex(string:lowercase(Value))
      end),
      gleam_json_string => attempt(fun() ->
          binary:encode_hex(iolist_to_binary(json:encode_binary(Value)))
      end)}.
attempt(Run) ->
    try #{ok => Run()}
    catch Class:_ -> #{error => atom_to_binary(Class)} end.
