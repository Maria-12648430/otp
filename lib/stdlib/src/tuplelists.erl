-module(tuplelists).

-export([delete/3, delete_with/3]).
-export([find/3, find_with/3]).
-export([map/4, map_with/3]).
-export([member/3, member_with/3]).
-export([merge/3, merge_with/4]).
-export([replace/4, replace_with/4]).
-export([sort/2, sort_with/3]).
-export([store/4, store_with/4]).
-export([take/3, take_with/3]).
-export([usort/2, usort_with/3]).
-export([umerge/3, umerge_with/4]).

%% ----------------------------------------------------------------------------
%% delete

-spec delete(KeyPos, Value, List1) -> List2
  when KeyPos :: pos_integer(),
       Value :: term(),
       List1 :: [tuple() | term()],
       List2 :: [tuple() | term()].
delete(KeyPos, Val, List) when is_integer(KeyPos), KeyPos>0 ->
    delete1(KeyPos, Val, List).

delete1(KeyPos, Val, [H|T]) when element(KeyPos, H)=:=Val ->
    T;
delete1(KeyPos, Val, [H|T]) ->
    [H|delete1(KeyPos, Val, T)];
delete1(_KeyPos, _Val, []) ->
    [].

-spec delete_with(KeyPos, Pred, List1) -> List2
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       List1 :: [tuple() | term()],
       List2 :: [tuple() | term()].
delete_with(KeyPos, Pred, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    delete_with1(KeyPos, Pred, List).

delete_with1(KeyPos, Pred, [H|T]) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    T;
	false ->
	    [H|delete_with1(KeyPos, Pred, T)]
    end;
delete_with1(KeyPos, Pred, [H|T]) ->
    [H|delete_with1(KeyPos, Pred, T)];
delete_with1(_KeyPos, _Pred, []) ->
    [].

%% ----------------------------------------------------------------------------
%% find

-spec find(KeyPos, Value, List) -> Found | error
  when KeyPos :: pos_integer(),
       Value :: term(),
       List :: [tuple() | term()],
       Found :: tuple().
find(KeyPos, Val, List) when is_integer(KeyPos), KeyPos>0 ->
    find1(KeyPos, Val, List).

find1(KeyPos, Val, [H|_T]) when element(KeyPos, H)=:=Val ->
    H;
find1(KeyPos, Val, [_H|T]) ->
    find1(KeyPos, Val, T);
find1(_KeyPos, _Val, []) ->
    error.

-spec find_with(KeyPos, Pred, List) -> Found | error
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       List :: [tuple() | term()],
       Found :: tuple().
find_with(KeyPos, Pred, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    find_with1(KeyPos, Pred, List).

find_with1(KeyPos, Pred, [H|T]) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    H;
	false ->
	    find_with1(KeyPos, Pred, T)
    end;
find_with1(KeyPos, Pred, [_H|T]) ->
    find_with1(KeyPos, Pred, T);
find_with1(_KeyPos, _Pred, []) ->
    error.

%% ----------------------------------------------------------------------------
%% map

-spec map(KeyPos, Value, New, List1) -> List2
  when KeyPos :: pos_integer(),
       Value :: term(),
       New :: term(),
       List1 :: [tuple() | term()],
       List2 :: [tuple() | term()].
map(KeyPos, Val, New, List) when is_integer(KeyPos), KeyPos>0 ->
    map1(KeyPos, Val, New, List).

map1(KeyPos, Val, New, [H|T]) when element(KeyPos, H)=:=Val ->
    [setelement(KeyPos, H, New)|map1(KeyPos, Val, New, T)];
map1(KeyPos, Val, New, [H|T]) ->
    [H|map1(KeyPos, Val, New, T)];
map1(_KeyPos, _Val, _New, []) ->
    [].

-spec map_with(KeyPos, Fun, List1) -> List2
  when KeyPos :: pos_integer(),
       Fun :: fun((term()) -> term()),
       List1 :: [tuple() | term()],
       List2 :: [tuple() | term()].
map_with(KeyPos, Fun, List) when is_integer(KeyPos), KeyPos>0, is_function(Fun, 1) ->
    map_with1(KeyPos, Fun, List).

map_with1(KeyPos, Fun, [H|T]) when tuple_size(H)>=KeyPos ->
    [setelement(KeyPos, H, Fun(element(KeyPos, H)))|map_with1(KeyPos, Fun, T)];
map_with1(KeyPos, Fun, [H|T]) ->
    [H|map_with1(KeyPos, Fun, T)];
map_with1(_KeyPos, _Fun, []) ->
    [].

%% ----------------------------------------------------------------------------
%% member

-spec member(KeyPos, Value, List) -> boolean()
  when KeyPos :: pos_integer(),
       Value :: term(),
       List :: [tuple() | term()].
member(KeyPos, Val, List) when is_integer(KeyPos), KeyPos>0 ->
    member1(KeyPos, Val, List).

member1(KeyPos, Val, [H|_T]) when element(KeyPos, H)=:=Val ->
    true;
member1(KeyPos, Val, [_H|T]) ->
    member1(KeyPos, Val, T);
member1(_KeyPos, _Val, []) ->
    false.

-spec member_with(KeyPos, Pred, List) -> boolean()
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       List :: [tuple() | term()].
member_with(KeyPos, Pred, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    member_with1(KeyPos, Pred, List).

member_with1(KeyPos, Pred, [H|T]) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    true;
	false ->
	    member_with1(KeyPos, Pred, T)
    end;
member_with1(KeyPos, Pred, [_H|T]) ->
    member_with1(KeyPos, Pred, T);
member_with1(_KeyPos, _Pred, []) ->
    false.

%% ----------------------------------------------------------------------------
%% merge

-spec merge(KeyPos, List1, List2) -> List3
  when KeyPos :: pos_integer(),
       List1 :: [tuple()],
       List2 :: [tuple()],
       List3 :: [tuple()].
merge(KeyPos, List1, List2) when is_integer(KeyPos), KeyPos>0 ->
    merge1(KeyPos, List1, List2).

merge1(_KeyPos, [], []) ->
    [];
merge1(KeyPos, List, []) ->
    case all_valid(KeyPos, List) of
        true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, List, []])
    end;
merge1(KeyPos, [], List) ->
    case all_valid(KeyPos, List) of
	true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, [], List])
    end;
merge1(KeyPos, List1, List2) ->
    lists:merge(fun (A, B) -> element(KeyPos, A)=<element(KeyPos, B) end, List1, List2).

-spec merge_with(KeyPos, Fun, List1, List2) -> List3
  when KeyPos :: pos_integer(),
       Fun :: fun((term(), term()) -> boolean()),
       List1 :: [tuple()],
       List2 :: [tuple()],
       List3 :: [tuple()].
merge_with(KeyPos, Fun, List1, List2) when is_integer(KeyPos), KeyPos>0, is_function(Fun, 2) ->
    merge_with1(KeyPos, Fun, List1, List2).

merge_with1(_KeyPos, _Fun, [], []) ->
    [];
merge_with1(KeyPos, Fun, List, []) ->
    case all_valid(KeyPos, List) of
        true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, Fun, List, []])
    end;
merge_with1(KeyPos, Fun, [], List) ->
    case all_valid(KeyPos, List) of
	true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, Fun, [], List])
    end;
merge_with1(KeyPos, Fun, List1, List2) ->
    lists:merge(fun (A, B) -> Fun(element(KeyPos, A), element(KeyPos, B)) end, List1, List2).

%% ----------------------------------------------------------------------------
%% replace

-spec replace(KeyPos, Value, New, List1) -> List2
  when KeyPos :: pos_integer(),
       Value :: term(),
       New :: tuple() | term(),
       List1 :: [tuple() | term()],
       List2 :: [New | tuple() | term()].
replace(KeyPos, Val, New, List) when is_integer(KeyPos), KeyPos>0 ->
    replace1(KeyPos, Val, New, List).

replace1(KeyPos, Val, New, [H|T]) when element(KeyPos, H)=:=Val ->
    [New|T];
replace1(KeyPos, Val, New, [H|T]) ->
    [H|replace1(KeyPos, Val, New, T)];
replace1(_KeyPos, _Val, _New, []) ->
    [].

-spec replace_with(KeyPos, Pred, New, List1) -> List2
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       New :: tuple() | term(),
       List1 :: [tuple() | term()],
       List2 :: [New | tuple() | term()].
replace_with(KeyPos, Pred, New, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    replace_with1(KeyPos, Pred, New, List).

replace_with1(KeyPos, Pred, New, [H|T]) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    [New|T];
	false ->
	    [H|replace_with1(KeyPos, Pred, New, T)]
    end;
replace_with1(KeyPos, Pred, New, [H|T]) ->
    [H|replace_with1(KeyPos, Pred, New, T)];
replace_with1(_KeyPos, _Pred, _New, []) ->
    [].

%% ----------------------------------------------------------------------------
%% sort

-spec sort(KeyPos, List1) -> List2
  when KeyPos :: pos_integer(),
       List1 :: [tuple()],
       List2 :: [tuple()].
sort(KeyPos, List) when is_integer(KeyPos), KeyPos>0 ->
    sort1(KeyPos, List).

sort1(KeyPos, List=[H]) when tuple_size(H)>=KeyPos ->
    List;
sort1(KeyPos, List=[_H1, _H2|_T]) ->
    lists:sort(fun (A, B) -> element(KeyPos, A)=<element(KeyPos, B) end, List);
sort1(KeyPos, List) ->
    erlang:error(badarg, [KeyPos, List]).

-spec sort_with(KeyPos, Fun, List1) -> List2
  when KeyPos :: pos_integer(),
       Fun :: fun((term(), term()) -> boolean()),
       List1 :: [tuple()],
       List2 :: [tuple()].
sort_with(KeyPos, Fun, List) when is_integer(KeyPos), KeyPos>0, is_function(Fun, 2) ->
    sort_with1(KeyPos, Fun, List).

sort_with1(KeyPos, _Fun, List=[H]) when tuple_size(H)>=KeyPos ->
    List;
sort_with1(KeyPos, Fun, List=[_H1, _H2|_T]) ->
    lists:sort(fun (A, B) -> Fun(element(KeyPos, A), element(KeyPos, B)) end, List);
sort_with1(KeyPos, Fun, List) ->
    erlang:error(badarg, [KeyPos, Fun, List]).

%% ----------------------------------------------------------------------------
%% store

-spec store(KeyPos, Value, New, List1) -> List2
  when KeyPos :: pos_integer(),
       Value :: term(),
       New :: tuple() | term(),
       List1 :: [tuple() | term()],
       List2 :: [New | tuple() | term()].
store(KeyPos, Val, New, List) when is_integer(KeyPos), KeyPos>0 ->
    case store1(KeyPos, Val, New, List, []) of
	false ->
	    [New|List];
	List1 ->
	    List1
    end.

store1(KeyPos, Val, New, [H|T], Acc) when element(KeyPos, H)=:=Val ->
    lists:reverse(Acc, [New|T]);
store1(KeyPos, Val, New, [H|T], Acc) ->
    store1(KeyPos, Val, New, T, [H|Acc]);
store1(_KeyPos, _Val, _New, [], _Acc) ->
    false.

-spec store_with(KeyPos, Pred, New, List1) -> List2
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       New :: tuple() | term(),
       List1 :: [tuple() | term()],
       List2 :: [New | tuple() | term()].
store_with(KeyPos, Pred, New, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    case store_with1(KeyPos, Pred, New, List, []) of
	false ->
	    [New|List];
	List1 ->
	    List1
    end.

store_with1(KeyPos, Pred, New, [H|T], Acc) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    lists:reverse(Acc, [New|T]);
	false ->
	    store_with1(KeyPos, Pred, New, T, [H|Acc])
    end;
store_with1(KeyPos, Pred, New, [H|T], Acc) ->
    store_with1(KeyPos, Pred, New, T, [H|Acc]);
store_with1(_KeyPos, _Pred, _New, [], _Acc) ->
    false.

%% ----------------------------------------------------------------------------
%% take

-spec take(KeyPos, Value, List1) -> {Found, List2} | error
  when KeyPos :: pos_integer(),
       Value :: term(),
       List1 :: [Found | tuple() | term()],
       Found :: tuple(),
       List2 :: [tuple() | term()].
take(KeyPos, Val, List) when is_integer(KeyPos), KeyPos>0 ->
    take1(KeyPos, Val, List, []).

take1(KeyPos, Val, [H|T], Acc) when element(KeyPos, H)=:=Val ->
    {H, lists:reverse(Acc, T)};
take1(KeyPos, Val, [H|T], Acc) ->
    take1(KeyPos, Val, T, [H|Acc]);
take1(_KeyPos, _Val, [], _Acc) ->
    error.

-spec take_with(KeyPos, Pred, List1) -> {Found, List2} | error
  when KeyPos :: pos_integer(),
       Pred :: fun((term()) -> boolean()),
       List1 :: [Found | tuple() | term()],
       Found :: tuple(),
       List2 :: [tuple() | term()].
take_with(KeyPos, Pred, List) when is_integer(KeyPos), KeyPos>0, is_function(Pred, 1) ->
    take_with1(KeyPos, Pred, List, []).

take_with1(KeyPos, Pred, [H|T], Acc) when tuple_size(H)>=KeyPos ->
    case Pred(element(KeyPos, H)) of
	true ->
	    {H, lists:reverse(Acc, T)};
	false ->
	    take_with1(KeyPos, Pred, T, [H|Acc])
    end;
take_with1(KeyPos, Pred, [H|T], Acc) ->
    take_with1(KeyPos, Pred, T, [H|Acc]);
take_with1(_KeyPos, _Pred, [], _Acc) ->
    error.

%% ----------------------------------------------------------------------------
%% umerge

-spec umerge(KeyPos, List1, List2) -> List3
  when KeyPos :: pos_integer(),
       List1 :: [tuple()],
       List2 :: [tuple()],
       List3 :: [tuple()].
umerge(KeyPos, List1, List2) when is_integer(KeyPos), KeyPos>0 ->
    umerge1(KeyPos, List1, List2).

umerge1(_KeyPos, [], []) ->
    [];
umerge1(KeyPos, List, []) ->
    case all_valid(KeyPos, List) of
        true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, List, []])
    end;
umerge1(KeyPos, [], List) ->
    case all_valid(KeyPos, List) of
	true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, [], List])
    end;
umerge1(KeyPos, List1, List2) ->
    lists:umerge(fun (A, B) -> element(KeyPos, A)=<element(KeyPos, B) end, List1, List2).

-spec umerge_with(KeyPos, Fun, List1, List2) -> List3
  when KeyPos :: pos_integer(),
       Fun :: fun((term(), term()) -> boolean()),
       List1 :: [tuple()],
       List2 :: [tuple()],
       List3 :: [tuple()].
umerge_with(KeyPos, Fun, List1, List2) when is_integer(KeyPos), KeyPos>0, is_function(Fun, 2) ->
    umerge_with1(KeyPos, Fun, List1, List2).

umerge_with1(_KeyPos, _Fun, [], []) ->
    [];
umerge_with1(KeyPos, Fun, List, []) ->
    case all_valid(KeyPos, List) of
        true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, Fun, List, []])
    end;
umerge_with1(KeyPos, Fun, [], List) ->
    case all_valid(KeyPos, List) of
	true ->
	    List;
	false ->
	    erlang:error(badarg, [KeyPos, Fun, [], List])
    end;
umerge_with1(KeyPos, Fun, List1, List2) ->
    lists:umerge(fun (A, B) -> Fun(element(KeyPos, A), element(KeyPos, B)) end, List1, List2).

%% ----------------------------------------------------------------------------
%% usort

-spec usort(KeyPos, List1) -> List2
  when KeyPos :: pos_integer(),
       List1 :: [tuple()],
       List2 :: [tuple()].
usort(KeyPos, List) when is_integer(KeyPos), KeyPos>0 ->
    usort1(KeyPos, List).

usort1(KeyPos, List=[H]) when tuple_size(H)>=KeyPos ->
    List;
usort1(KeyPos, List=[_H1, _H2|_T]) ->
    lists:usort(fun (A, B) -> element(KeyPos, A)=<element(KeyPos, B) end, List);
usort1(KeyPos, List) ->
    erlang:error(badarg, [KeyPos, List]).

-spec usort_with(KeyPos, Fun, List1) -> List2
  when KeyPos :: pos_integer(),
       Fun :: fun((term(), term()) -> boolean()),
       List1 :: [tuple()],
       List2 :: [tuple()].
usort_with(KeyPos, Fun, List) when is_integer(KeyPos), KeyPos>0, is_function(Fun, 2) ->
    usort_with1(KeyPos, Fun, List).

usort_with1(KeyPos, _Fun, List=[H]) when tuple_size(H)>=KeyPos ->
    List;
usort_with1(KeyPos, Fun, List=[_H1, _H2|_T]) ->
    lists:usort(fun (A, B) -> Fun(element(KeyPos, A), element(KeyPos, B)) end, List);
usort_with1(KeyPos, Fun, List) ->
    erlang:error(badarg, [KeyPos, Fun, List]).


%% HELPER FUNCTIONS

all_valid(KeyPos, List) ->
    lists:all(
	fun
	    (E) when tuple_size(E)>=KeyPos ->
		true;
	    (_E) ->
		false
	end,
	List
    ).
