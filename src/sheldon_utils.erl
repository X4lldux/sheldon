%%% @doc Utils module for sheldon.
%%%
%%% Copyright 2016 Inaka &lt;hello@inaka.net&gt;
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @end
%%% @copyright Inaka <hello@inaka.net>
%%%
-module(sheldon_utils).
-author("Felipe Ripoll <ferigis@gmail.com>").

%% API
-export([ normalize/1
        , is_number/1
        , match_in_patterns/2
        ]).

-compile({no_auto_import, [is_number/1]}).

%%%===================================================================
%%% API
%%%===================================================================

-spec normalize(string()) -> string().
normalize(Word) ->
  CharToScape = [ "\n"
                , "."
                , ","
                , ":"
                , ";"
                , "?"
                , ")"
                , "("
                , "\""
                , "\'"
                , "!"
                , "["
                , "]"
                , "{"
                , "}"
                , "`"
                ],
  Word1 = escape_chars(Word, CharToScape),
  [WordBin | _] = re:split(Word1, "'s"),
  binary_to_list(WordBin).

-spec is_number(string()) -> boolean().
is_number(Word) ->
  re:run(Word, "^[0-9]*$") =/= nomatch.

-spec match_in_patterns(string(), [string()]) -> boolean().
match_in_patterns(Word, Patterns) ->
  MatchTuples = [{Word, Pattern} || Pattern <- Patterns],
  lists:foldl(fun match/2, false, MatchTuples).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec escape_chars(string(), [string()]) -> string().
escape_chars(Word, []) -> Word;
escape_chars(Word, [Character | Rest]) ->
  case string:tokens(Word, Character) of
    []          -> escape_chars(Word, []);
    [Word1 | _] -> escape_chars(Word1, Rest)
  end.

-spec match({string(), string()}, boolean()) -> boolean().
match(_, true) -> true;
match({Word, Pattern}, false) ->
  re:run(Word, Pattern) =/= nomatch.
