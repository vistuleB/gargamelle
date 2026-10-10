-module(plan_support).
-export([counter/1, handoff/1, measure/1, fresh_identity/0]).
fresh_identity() -> make_ref().
measure(Run) ->
    {reductions, Before} = process_info(self(), reductions),
    {Micros, _} = timer:tc(Run),
    {reductions, After} = process_info(self(), reductions),
    {Micros, After - Before}.
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
