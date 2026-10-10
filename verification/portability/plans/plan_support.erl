-module(plan_support).
-export([counter/1, handoff/1, measure/1, fresh_identity/0, transfer_size/2]).
fresh_identity() -> make_ref().
%% Diagnostic only: size counts heap sharing; flat_size counts repeated edges.
%% Measure the received term as well, rather than assuming message-copy behavior.
transfer_size(Value, Use) ->
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        receive {inspect, Term} ->
            Size = erts_debug:size(Term),
            Use(Term),
            Parent ! {size, self(), Size}
        end
    end),
    Shared = erts_debug:size(Value),
    Flat = erts_debug:flat_size(Value),
    Pid ! {inspect, Value},
    Received = receive
        {size, Pid, Words} -> Words;
        {'DOWN', Monitor, process, Pid, Reason} -> error({transfer_failed, Reason})
    after 10000 -> error(transfer_timeout) end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok
    after 10000 -> error(exit_timeout) end,
    {Shared, Flat, Received}.
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
