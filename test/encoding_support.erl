-module(encoding_support).
-export([invalid_text/0]).
invalid_text() -> <<16#ED, 16#A0, 16#80>>.
