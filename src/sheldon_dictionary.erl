%%% @doc This gen_server only creates the ets for the dictionary and
%%%      ets for bazingas. This module also provides the 'candidates' feature.
%%%      That feature returns the list of candidates when one word is
%%%      misspelled and it also manages an ets table.
%%%
%%% Copyright Erlang Solutions Ltd. 2017 &lt;hello@inaka.net&gt;
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
%%% @copyright Erlang Solutions Ltd. <hello@inaka.net>
%%%
-module(sheldon_dictionary).
-author("Felipe Ripoll <felipe@inakanetworks.com>").

-behaviour(gen_server).

%% API
-export([ start_link/1
        , member/2
        , dictionary_name/1
        , get_bazinga/1
        , candidates/2
        , dump_dict_to_bin/1
        ]).

%% gen_server callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-export_type([ language/0
             ]).

-type language() :: eng.

%%%===================================================================
%%% API
%%%===================================================================

%% @doc starts the gen_server
-spec start_link(language()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}.
start_link(Lang) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [Lang], []).

%% @doc evaluates if a given string() is member of the dictionary
-spec member(string(), language()) -> boolean().
member(Word, Lang) ->
  DictName = dictionary_name(Lang),
  WordLower = string:to_lower(Word),
  ets:lookup(DictName, list_to_binary(WordLower)) =/= [].

%% @doc returns a bazinga from the ETS
-spec get_bazinga(language()) -> string().
get_bazinga(Lang) ->
  BazingaName = bazinga_name(Lang),
  Keys = ets:tab2list(BazingaName),
  {Bazinga} = lists:nth(rand:uniform(length(Keys)), Keys),
  Bazinga.

%% @doc returns the name of the dictionary given the language() as a
%%      parameter
-spec dictionary_name(language()) -> atom().
dictionary_name(Lang) ->
  Bin = << (atom_to_binary(sheldon, utf8))/binary
         , "_"
         , (atom_to_binary(Lang, utf8))/binary>>,
  binary_to_atom(Bin, utf8).

%% @doc saves dictionary to its binary format for a given language() which
%%      will result in faster loading time
-spec dump_dict_to_bin(language()) -> atom().
dump_dict_to_bin(Lang) ->
  BinLangSource = dictionary_path(binary, Lang),
  EtsName = dictionary_name(Lang),
  ets:tab2file(EtsName, BinLangSource),
  ok.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec init([language()]) -> {ok, State :: map()}.
init([Lang]) ->
  ok = learn_language(Lang),
  ok = set_bazingas(Lang),
  {ok, #{}}.

-spec handle_call( Request :: term()
                 , From    :: {pid()
                 , Tag     :: term()}
                 , State
                 ) -> {reply, ok, State}.
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

-spec handle_cast(Request :: term(), State) ->
  {noreply, State}.
handle_cast(_Request, State) ->
  {noreply, State}.

-spec handle_info(Info :: timeout() | term(), State) ->
  {noreply, State}.
handle_info(_Info, State) ->
  {noreply, State}.

-spec terminate( Reason :: (normal | shutdown | {shutdown, term()} | term())
               , State  :: map()
               ) -> term().
terminate(_Reason, _State) ->
  ok.

-spec code_change(OldVsn :: term() | {down, term()}
                 , State
                 , Extra :: term()
                 ) -> {ok, State}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

-spec learn_language(language()) -> ok.
learn_language(Lang) ->
  LangSource = dictionary_path(text, Lang),
  BinLangSource = dictionary_path(binary, Lang),
  DictionaryName = dictionary_name(Lang),
  case fill_ets(DictionaryName, LangSource, BinLangSource) of
    {text_dict, Words} ->
      %% save the keys in set format in order to suggest words
      KeysSet = mapsets:from_list(Words),
      ets:insert(DictionaryName, {keys, KeysSet}),
      ok;
    bin_dict ->
      %% binary format already has keys loaded
      ok
  end.

-spec set_bazingas(language()) -> ok.
set_bazingas(Lang) ->
  BazingaSource = [ code:priv_dir(sheldon)
                  , "/lang/"
                  , atom_to_list(Lang)
                  , "/bazinga.txt"
                  ],
  BazingaName = bazinga_name(Lang),
  _Bazingas = fill_ets(BazingaName, BazingaSource, []),
  ok.

-spec bazinga_name(language()) -> atom().
bazinga_name(Lang) ->
  Bin = << (atom_to_binary(bazinga, utf8))/binary
         , "_"
         , (atom_to_binary(Lang, utf8))/binary>>,
  binary_to_atom(Bin, utf8).

-spec fill_ets(atom(), term(), term()) -> bin_dict | {text_dict, [binary()]}.
fill_ets(EtsName, Source, BinSource) ->
  case filelib:is_regular(BinSource) of
    true ->
      ets:file2tab(BinSource, [{verify, true}]),
      bin_dict;

    false ->
      {ok, SourceBin} = file:read_file(Source),
      Words = re:split(SourceBin, "\n"), % one word per line
      ok = create_ets(EtsName),
      ets:insert(EtsName, [{Word} || Word <- Words]),
      {text_dict, Words}
  end.

-spec create_ets(atom()) -> ok.
create_ets(EtsName) ->
  EtsName = ets:new(EtsName, [named_table, duplicate_bag, {read_concurrency, true}]),
  ok.

-spec dictionary_path(text | binary, language()) -> iolist().
dictionary_path(text, Lang) ->
  do_dictionary_path("txt", Lang);
dictionary_path(binary, Lang) ->
  do_dictionary_path("bin", Lang).

-spec do_dictionary_path(string(), atom()) -> iolist().
do_dictionary_path(Ext, Lang) ->
  [ code:priv_dir(sheldon)
  , "/lang/"
  , atom_to_list(Lang)
  , "/dictionary."
  , Ext
  ].

%%%===================================================================
%%% Corrector Internal Funcions
%%%===================================================================

-spec candidates(string(), language()) -> [string()].
candidates(WordStr, Lang) ->
  Word = list_to_binary(string:to_lower(WordStr)),
  Set1 = mapsets:add_element(Word, empty_set()),
  Set2 = mapsets:from_list(edits1(Word)),
  Set3 = mapsets:from_list(edits2(Word)),
  Candidates = know_sets(Word, [Set1, Set2, Set3], Lang),
  [binary_to_list(Bin) || Bin <- Candidates].

-spec know_sets(binary(), [mapsets:set()], language()) -> [binary()].
know_sets(Word, [], _Lang) ->
  [Word];
know_sets(Word, [Set | Sets], Lang) ->
  EmptySet = empty_set(),
  case know(Set, Lang) of
    EmptySet -> know_sets(Word, Sets, Lang);
    Words    -> mapsets:to_list(Words)
  end.

-spec know(mapsets:set(), language()) -> mapsets:set().
know(WordsSet, Lang) ->
  [{keys, KeysSet}] = ets:lookup(dictionary_name(Lang), keys),
  mapsets:intersection(WordsSet, KeysSet).

-spec edits1(binary()) -> [binary()].
edits1(WordBinary) ->
  Word = binary_to_list(WordBinary),
  Splits = [lists:split(I, Word) || I <- lists:seq(0, length(Word))],
  Acc1 = deletes(Splits, []),
  Acc2 = transposes(Splits, Acc1),
  Acc3 = replaces(Splits, Acc2),
  Acc4 = inserts(Splits, Acc3),
  lists:flatten(Acc4).

-spec deletes([tuple()], list()) -> list().
deletes(Splits, Acc) ->
  Result = [iolist_to_binary([Left, Right]) || {Left, [_ | Right]} <- Splits],
  [Result | Acc].

-spec transposes([tuple()], list()) -> list().
transposes(Splits, Acc) ->
  Result = [iolist_to_binary([Left, B, A, Right])
    || {Left, [A, B | Right]} <- Splits],
  [Result | Acc].

-spec replaces([tuple()], list()) -> list().
replaces(Splits, Acc) ->
  Result = [iolist_to_binary([Left, Char, Right])
    || {Left, [_ | Right]} <- Splits, Char <- chars()],
  [Result | Acc].

-spec inserts([tuple()], list()) -> list().
inserts(Splits, Acc) ->
  Result = [iolist_to_binary([Left, Char, Right])
    || {Left, Right} <- Splits, Char <- chars()],
  [Result | Acc].

-spec edits2(binary()) -> [binary()].
edits2(Word) ->
  Result = [edits1(E1) || E1 <- edits1(Word)],
  lists:flatten(Result).

-spec chars() -> string().
chars() ->
  "abcdefghijklmnopqrstuvwxyz".

-spec empty_set() -> mapsets:set().
empty_set() ->
  mapsets:new().
