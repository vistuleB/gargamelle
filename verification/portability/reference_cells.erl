%% Research prototype, deliberately outside src. The core Definition/Node
%% representation must carry frozen contexts before this can become a backend.
-module(reference_cells).
-export([with_construction/1, with_context/2, new/2, selftest/0]).
-define(KEY, '$gargamelle_portability_cells').

with_construction(Build) ->
    scoped(#{}, fun() ->
        Value = Build(),
        {Value, get(?KEY)}
    end).
with_context(Context, Run) -> scoped(Context, Run).
scoped(Context, Run) ->
    Previous = get(?KEY),
    put(?KEY, Context),
    try Run()
    after
        case Previous of
            undefined -> erase(?KEY);
            _ -> put(?KEY, Previous)
        end
    end.

%% Each cell's read/bind closures share one fresh key. Bound values are returned
%% unchanged, through the same private typed factory interface as the JS cell.
%% No generic value conversion or cast is used.
new(Make, Missing) ->
    Key = make_ref(),
    Read = fun() ->
        case state(Key) of
            {bound, Value} -> {ok, Value};
            _ -> {error, Missing}
        end
    end,
    Bind = fun(Value) ->
        case state(Key) of
            unbound -> set(Key, {bound, Value});
            _ -> error(already_finalized)
        end
    end,
    Reject = fun() -> set(Key, rejected) end,
    set(Key, unbound),
    Make(Read, Bind, Reject).
state(Key) ->
    case get(?KEY) of
        Context when is_map(Context) -> maps:get(Key, Context, unavailable);
        _ -> unavailable
    end.
set(Key, Value) ->
    case get(?KEY) of
        Context when is_map(Context) -> put(?KEY, maps:put(Key, Value, Context)), nil;
        _ -> error(no_construction_context)
    end.

selftest() ->
    undefined = get(?KEY),
    {Read, Context} = with_construction(fun() ->
        {R, Bind, _} = new(fun(A, B, C) -> {A, B, C} end, missing),
        {error, missing} = R(),
        nil = Bind(42),
        {ok, 42} = R(),
        expect(already_finalized, fun() -> Bind(43) end),
        R
    end),
    undefined = get(?KEY),
    {error, missing} = Read(),
    {ok, 42} = with_context(Context, Read),
    undefined = get(?KEY),
    expect(callback_failure, fun() ->
        with_context(Context, fun() -> error(callback_failure) end)
    end),
    undefined = get(?KEY),
    {RejectedRead, Rejected} = with_construction(fun() ->
        {R, Bind, Reject} = new(fun(A, B, C) -> {A, B, C} end, missing),
        nil = Bind(12),
        nil = Reject(),
        {error, missing} = R(),
        expect(already_finalized, fun() -> Bind(13) end),
        R
    end),
    {error, missing} = with_context(Rejected, RejectedRead),
    %% A recursive converter resolves its own typed function cell at use time.
    {RecursiveRead, RecursiveContext} = with_construction(fun() ->
        {R, Bind, _} = new(fun(A, B, C) -> {A, B, C} end, missing),
        nil = Bind(fun
            (0) -> 0;
            (N) -> {ok, Convert} = R(), Convert(N - 1) + 1
        end),
        R
    end),
    50 = with_context(RecursiveContext, fun() ->
        {ok, Convert} = RecursiveRead(), Convert(50)
    end),
    %% Cross references can retain independent decoded output shapes.
    {{FirstRead, SecondRead}, PairContext} = with_construction(fun() ->
        {A, BindA, _} = new(fun(R, B, C) -> {R, B, C} end, missing),
        {B, BindB, _} = new(fun(R, Bind, C) -> {R, Bind, C} end, missing),
        nil = BindA(fun
            (0) -> {number, 0};
            (N) -> {ok, ConvertB} = B(), {number, N, ConvertB(N - 1)}
        end),
        nil = BindB(fun
            (0) -> [<<"text">>];
            (N) -> {ok, ConvertA} = A(), [<<"text">>, ConvertA(N - 1)]
        end),
        {A, B}
    end),
    {number, 2, [<<"text">>, {number, 0}]} = with_context(PairContext, fun() ->
        {ok, Convert} = FirstRead(), Convert(2)
    end),
    [<<"text">>, {number, 1, [<<"text">>]}] = with_context(PairContext, fun() ->
        {ok, Convert} = SecondRead(), Convert(2)
    end),
    %% Definitions must work after their constructing process exits.
    Parent = self(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Frozen = with_construction(fun() ->
            {R, Bind, _} = new(fun(A, B, C) -> {A, B, C} end, missing),
            nil = Bind(fun(Value) -> Value + 1 end),
            R
        end),
        Parent ! {frozen, self(), Frozen}
    end),
    Frozen = receive {frozen, Pid, F} -> F after 2000 -> error(handoff_timeout) end,
    receive {'DOWN', Monitor, process, Pid, normal} -> ok
        after 2000 -> error(exit_timeout) end,
    {Transferred, Snapshot} = Frozen,
    42 = with_context(Snapshot, fun() ->
        {ok, Convert} = Transferred(),
        Convert(41)
    end),
    %% A nested scope must restore the outer snapshot, including on failure.
    {ok, 42} = with_context(Context, fun() ->
        expect(callback_failure, fun() ->
            with_context(Rejected, fun() -> error(callback_failure) end)
        end),
        Read()
    end),
    undefined = get(?KEY),
    #{handoff => true, once_bound => true, rejection => true, cleanup => true, recursion => true, independent_types => true}.
expect(Reason, Run) ->
    try Run() of _ -> error({expected_failure, Reason})
    catch error:Reason -> ok
    end.
