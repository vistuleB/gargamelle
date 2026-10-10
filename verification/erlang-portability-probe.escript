#!/usr/bin/env escript
%% Native OTP/gleam_json baseline only; this does not exercise an Erlang
%% Gargamelle backend. Run from the repository after gleam deps download.
main(_) ->
    io:format("OTP ~s~n", [erlang:system_info(otp_release)]),
    {ok, gleam_json_ffi, Beam} = compile:file(
        "build/packages/gleam_json/src/gleam_json_ffi.erl", [binary]),
    {module, gleam_json_ffi} = code:load_binary(gleam_json_ffi, "probe", Beam),
    Cases = [<<"9007199254740993">>, <<"1e400">>, <<"1e-400">>,
        <<"-0">>, <<"-0.0">>, <<"\"\\ud800\"">>,
        <<"{\"a\":1,\"a\":2}">>],
    lists:foreach(fun(Input) ->
        try gleam_json_ffi:decode(Input) of
            Result -> io:format("~s -> ~p~n", [Input, Result])
        catch Class:Reason ->
            io:format("~s -> ~p:~p~n", [Input, Class, Reason])
        end
    end, Cases),
    io:format("dot on U+2028 -> ~p~n",
        [re:run(<<16#2028/utf8>>, <<"^.$">>, [unicode])]),
    io:format("float encoding -> ~s, ~s, ~s~n",
        [json:encode(1.0), json:encode(1.0e-7), json:encode(-0.0)]).
