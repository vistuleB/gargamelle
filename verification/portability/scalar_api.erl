%% Test adapter only: Canonical serialization and native regex semantics.
%% Never attach these regex functions to the public supported backend.
-module(scalar_api).
-export([canonical/1, pattern_valid/1, pattern_matches/2, handoff/1,
         exception_cleanup/1]).
canonical(Source) ->
    {ok, Text} = gargamelle_runtime:canonical_scalar_json(Source), Text.
pattern_valid(Pattern) -> case re:compile(Pattern, [unicode]) of
    {ok, _} -> true;
    {error, _} -> false
end.
pattern_matches(Pattern, Text) -> case re:run(Text, Pattern, [unicode, {capture, none}]) of
    match -> true;
    nomatch -> false;
    {error, Reason} -> error({regex_failure, Reason})
end.
handoff(Build) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() -> Parent ! {built, self(), Build()} end),
    Value = receive {built, Pid, Built} -> Built after 3000 -> error(build_timeout) end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok
        after 3000 -> error(exit_timeout) end,
    Value.

%% An operational exception must escape while both scoped registries restore
%% their previous values, including when called from an enclosing operation.
exception_cleanup(Run) ->
    Keys = ['$gargamelle_cells', '$gargamelle_walk'],
    Before = [get(K) || K <- Keys],
    Raised = try Run(), false catch _:_ -> true end,
    Raised andalso Before =:= [get(K) || K <- Keys].
