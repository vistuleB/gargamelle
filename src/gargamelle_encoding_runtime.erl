-module(gargamelle_encoding_runtime).
-export([scalar/1]).

%% Inspect the binary before serialization. Invalid UTF-8 and surrogate encodings
%% are rejected; operational errors and invalid foreign argument types propagate.
scalar(Text) when is_binary(Text) ->
    case unicode:characters_to_list(Text, utf8) of
        Characters when is_list(Characters) -> true;
        {error, _, _} -> false;
        {incomplete, _, _} -> false
    end.
