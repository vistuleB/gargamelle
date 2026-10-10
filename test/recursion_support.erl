-module(recursion_support).
-export([counter/1, handoff/1]).
counter(Make) ->
    Counter = atomics:new(1, []),
    Make(fun() -> atomics:add(Counter, 1, 1), nil end,
         fun() -> atomics:get(Counter, 1) end).
handoff(Build) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() -> Parent ! {built, self(), Build()} end),
    Value = receive
        {built, Pid, Built} -> Built;
        {'DOWN', Monitor, process, Pid, Reason} -> error({builder_failed, Reason})
    after 3000 -> error(build_timeout) end,
    receive {'DOWN', Monitor, process, Pid, normal} -> Value
    after 3000 -> error(exit_timeout) end.
