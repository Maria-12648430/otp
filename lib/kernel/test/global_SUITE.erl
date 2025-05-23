%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1997-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(global_SUITE).

%% Prior to OTP 26, maybe_expr used to require runtime support. As it's now
%% enabled by default, all modules are tagged with the feature even when they
%% don't use it. Therefore, we explicitly disable it until OTP 25 is out of
%% support.
-feature(maybe_expr, disable).
-compile(r25). % many_nodes()

-export([all/0, suite/0, groups/0, 
	 init_per_suite/1, end_per_suite/1,
         init_per_group/2,end_per_group/2,
         init_per_testcase/2, end_per_testcase/2,

	 names/1, names_hidden/1, locks/1, locks_hidden/1,
	 bad_input/1, names_and_locks/1, lock_die/1, name_die/1,
	 basic_partition/1, basic_name_partition/1,
	 advanced_partition/1, stress_partition/1,
	 ring/1, simple_ring/1, line/1, simple_line/1,
	 global_lost_nodes/1, otp_1849/1,
	 otp_3162/1, otp_5640/1, otp_5737/1,
         connect_all_false/1, 
         simple_disconnect/1, 
         simple_resolve/1, simple_resolve2/1, simple_resolve3/1,
         leftover_name/1, re_register_name/1, name_exit/1, external_nodes/1,
         many_nodes/1, sync_0/1,
	 global_groups_change/1,
	 register_1/1,
	 both_known_1/1,
         lost_unregister/1,
	 mass_death/1,
	 garbage_messages/1,
         ring_line/1,
         flaw1/1,
         lost_connection/1,
         lost_connection2/1,
         global_disconnect/1
        ]).

%% Not used
-export([config_dc/4,
         w/2,
         check_same/2,
         check_same/1,
         stop/0,
         start_nodes_serially/3]).

-export([lock_global/2, lock_global2/2]).

-export([
         %% Called via ?RES
         resolve_none/3,
         resolve_first/3,
         resolve_second/3,
         bad_resolver/3,
         badrpc_resolver/3,
         lock_resolver/3,
         exit_resolver/3,
         disconnect_first/3,
         halt_second/3,
         init_mass_spawn/1,

         %% Called via rpc_cast
         crash/1,
         single_node/2,
         alone/2,
         global_load/3,

         %% Called via rpc:call
         halt_node/1,
         start_proc/0, start_proc/1,
         start_proc2/1,
         start_proc3/1,
         start_proc4/1,
         start_proc_basic/1,
         start_resolver/2,

         %% Called as a fun (fun ?MODULE:function/x) 
         fix_basic_name/3,

         %% Called via spawn
         init_proc_basic/2,
         init_2/0,
         p_init/1, p_init/2,
         p_init2/2

        ]).

-export([start_tracer/0, stop_tracer/0, get_trace/0]).

%% Exports for error_logger handler
-export([init/1, handle_event/2, handle_info/2, handle_call/2, terminate/2]).


-include_lib("common_test/include/ct.hrl").
-include("kernel_test_lib.hrl").

-define(NODES, [node()|nodes()]).

-define(UNTIL(Seq), loop_until_true(fun() -> Seq end, Config, 1)).

%% The resource used by the global module.
-define(GLOBAL_LOCK, global).

%% -define(DBG(T), erlang:display({{self(), ?MODULE, ?LINE, ?FUNCTION_NAME}, T})).


suite() ->
    [{ct_hooks,[ts_install_cth]}].

all() -> 
    case init:get_argument(ring_line) of
	{ok, _} -> [ring_line];
	_ ->
	    [
             names, names_hidden, locks, locks_hidden, bad_input,
	     names_and_locks, lock_die, name_die, basic_partition,
	     advanced_partition, basic_name_partition,
	     stress_partition, simple_ring, simple_line, ring, line,
	     global_lost_nodes, otp_1849, otp_3162, otp_5640,
	     otp_5737, connect_all_false, simple_disconnect, simple_resolve,
	     simple_resolve2, simple_resolve3, leftover_name,
	     re_register_name, name_exit, external_nodes, many_nodes,
	     sync_0, global_groups_change, register_1, both_known_1,
	     lost_unregister, mass_death, garbage_messages, flaw1,
             lost_connection, lost_connection2, global_disconnect
            ]
    end.

groups() -> 
    [{ttt, [],
      [names, names_hidden, locks, locks_hidden, bad_input,
       names_and_locks, lock_die, name_die, basic_partition,
       ring]}].

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.


-define(TESTCASE, testcase_name).
-define(testcase, proplists:get_value(?TESTCASE, Config)).
-define(nodes_tag, '$global_nodes').
-define(registered, proplists:get_value(registered, Config)).

init_per_testcase(Case, Config0) when is_atom(Case) andalso is_list(Config0) ->
    start_node_tracker(Config0),

    ?P("init_per_testcase -> entry with"
       "~n   Config:   ~p"
       "~n   Nodes:    ~p"
       "~n   Links:    ~p"
       "~n   Monitors: ~p",
       [Config0, erlang:nodes(), pi(links), pi(monitors)]),

    ok = gen_server:call(global_name_server,
                         high_level_trace_start,
                         infinity),

    Config1 = [{?TESTCASE, Case}, {registered, registered()} | Config0],

    ?P("init_per_testcase -> done when"
       "~n   Config:   ~p"
       "~n   Nodes:    ~p"
       "~n   Links:    ~p"
       "~n   Monitors: ~p", [Config1, erlang:nodes(), pi(links), pi(monitors)]),

    Config1.

end_per_testcase(_Case, Config) ->
    ?P("end_per_testcase -> entry with"
       "~n   Config:   ~p"
       "~n   Nodes:    ~p"
       "~n   Links:    ~p"
       "~n   Monitors: ~p",
       [Config, erlang:nodes(), pi(links), pi(monitors)]),

    write_high_level_trace(Config),
    _ = gen_server:call(global_name_server, high_level_trace_stop, infinity),
    [global:unregister_name(N) || N <- global:registered_names()],
    InitRegistered = ?registered,
    Registered = registered(),

    [?P("end_per_testcase -> "
        "~n   ~s local names: ~p", [What, N]) ||
	{What, N} <- [{"Added", Registered -- InitRegistered},
		      {"Removed", InitRegistered -- Registered}],
	N =/= []],

    ?P("end_per_testcase -> done with"
       "~n   Nodes:    ~p"
       "~n   Links:    ~p"
       "~n   Monitors: ~p",
       [erlang:nodes(), pi(links), pi(monitors)]),

    stop_node_tracker(Config). %% Needs to be last and produce return value...

%%% General comments:
%%% One source of problems with failing tests can be that the nodes from the
%%% previous test haven't died yet.
%%% So, when stressing a particular test by running it in a loop, it may
%%% fail already when starting the help nodes, even if the nodes have been
%%% monitored and the nodedowns picked up at the previous round. Waiting
%%% a few seconds between rounds seems to solve the problem. Possibly the
%%% timeout of 7 seconds for connections can also be a problem. This problem
%%% is the same with old (vsn 3) and new global (vsn 4).


%%% Test that register_name/2 registers the name on all nodes, even if
%%% a new node appears in the middle of the operation (OTP-3552).
%%%
%%% Test scenario: process p2 is spawned, locks global, starts a slave node,
%%% and tells the parent to do register_name. Then p2 sleeps for five seconds
%%% and releases the lock. Now the name should exist on both our own node
%%% and on the slave node (we wait until that is true; it seems that we
%%% can do rpc calls to another node before the connection is really up).
register_1(Config) when is_list(Config) ->
    Timeout = 15,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    P = spawn_link(?MODULE, lock_global, [self(), Config]),
    receive
	{P, ok} ->
	    io:format("p1: received ok~n"),
	    ok
    end,
    P ! step2,
    io:format("p1: sent step2~n"),
    yes = global:register_name(foo, self()),
    io:format("p1: registered~n"),
    P ! step3,
    receive
	{P, I, I2} ->
	    ok
    end,
    if
	I =:= I2 ->
	    ok;
	true ->
	    ct:fail({notsync, I, I2})
    end,
    _ = global:unregister_name(foo),
    write_high_level_trace(Config),
    init_condition(Config),
    ok.

lock_global(Parent, Config) ->
    Id = {global, self()},
    io:format("p2: setting lock~n"),
    global:set_lock(Id, [node()]),
    Parent ! {self(), ok},
    io:format("p2: sent ok~n"),
    receive
	step2 ->
	    io:format("p2: received step2"),
	    ok
    end,
    io:format("p2: starting slave~n"),
    {ok, Host} = inet:gethostname(),
    {ok, N1} = slave:start(Host, node1),
    io:format("p2: deleting lock~n"),
    global:del_lock(Id, [node()]),
    io:format("p2: deleted lock~n"),
    receive
	step3 ->
	    ok
    end,
    io:format("p2: received step3~n"),
    I = global:whereis_name(foo),
    io:format("p2: name ~p~n", [I]),
    ?UNTIL(I =:= rpc:call(N1, global, whereis_name, [foo])),
    I2 = I,
    slave:stop(N1),
    io:format("p2: name2 ~p~n", [I2]),
    Parent ! {self(), I, I2},
    ok.

%%% Test for the OTP-3576 problem: if nodes 1 and 2 are separated and
%%% brought together again, while keeping connection with 3, it could
%%% happen that if someone temporarily held the 'global' lock,
%%% 'try_again_locker' would be called, and this time cause both 1 and 2
%%% to obtain a lock for 'global' on node 3, which would keep the
%%% name registry from ever becoming consistent again.
both_known_1(Config) when is_list(Config) ->
    case prevent_overlapping_partitions() of
        true ->
            {skipped, "Prevent overlapping partitions enabled"};
        false ->
            both_known_1_test(Config)
    end.

both_known_1_test(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),

    OrigNames = global:registered_names(),

    [Cp1, Cp2, Cp3] = start_nodes([cp1, cp2, cp3], slave, Config),

    wait_for_ready_net(Config),

    rpc_disconnect_node(Cp1, Cp2, Config),

    {_Pid1, yes} = rpc:call(Cp1, ?MODULE, start_proc, [p1]),
    {_Pid2, yes} = rpc:call(Cp2, ?MODULE, start_proc, [p2]),

    Names10 = rpc:call(Cp1, global, registered_names, []),
    Names20 = rpc:call(Cp2, global, registered_names, []),
    Names30 = rpc:call(Cp3, global, registered_names, []),

    Names1 = Names10 -- OrigNames,
    Names2 = Names20 -- OrigNames,
    Names3 = Names30 -- OrigNames,

    [p1] = lists:sort(Names1),
    [p2] = lists:sort(Names2),
    [p1, p2] = lists:sort(Names3),

    Locker = spawn(Cp3, ?MODULE, lock_global2, [{global, l3},
						self()]),

    receive
	{locked, S} ->
	    true = S
    end,

    pong = rpc:call(Cp1, net_adm, ping, [Cp2]),

    %% Bring cp1 and cp2 together, while someone has locked global.
    %% They will now loop in 'loop_locker'.

    Names10_2 = rpc:call(Cp1, global, registered_names, []),
    Names20_2 = rpc:call(Cp2, global, registered_names, []),
    Names30_2 = rpc:call(Cp3, global, registered_names, []),

    Names1_2 = Names10_2 -- OrigNames,
    Names2_2 = Names20_2 -- OrigNames,
    Names3_2 = Names30_2 -- OrigNames,

    [p1] = lists:sort(Names1_2),
    [p2] = lists:sort(Names2_2),
    [p1, p2] = lists:sort(Names3_2),

    %% Let go of the lock, and expect the lockers to resolve the name
    %% registry.
    Locker ! {ok, self()},

    ?UNTIL(begin
	       Names10_3 = rpc:call(Cp1, global, registered_names, []),
	       Names20_3 = rpc:call(Cp2, global, registered_names, []),
	       Names30_3 = rpc:call(Cp3, global, registered_names, []),

	       Names1_3 = Names10_3 -- OrigNames,
	       Names2_3 = Names20_3 -- OrigNames,
	       Names3_3 = Names30_3 -- OrigNames,

	       N1 = lists:sort(Names1_3),
	       N2 = lists:sort(Names2_3),
	       N3 = lists:sort(Names3_3),
	       (N1 =:= [p1, p2]) and (N2 =:= [p1, p2]) and (N3 =:= [p1, p2])
	   end),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),

    init_condition(Config),
    ok.

%% OTP-6428. An unregistered name reappears.
lost_unregister(Config) when is_list(Config) ->
    case prevent_overlapping_partitions() of
        true ->
            {skipped, "Prevent overlapping partitions enabled"};
        false ->
            lost_unregister_test(Config)
    end.

lost_unregister_test(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),

    {ok, B} = start_node(b, Config),
    {ok, C} = start_node(c, Config),
    Nodes = [node(), B, C],

    wait_for_ready_net(Config),

    %% start a proc and register it
    {Pid, yes} = start_proc(test),

    ?UNTIL(Pid =:= global:whereis_name(test)),
    check_everywhere(Nodes, test, Config),

    rpc_disconnect_node(B, C, Config),
    check_everywhere(Nodes, test, Config),
    _ = rpc:call(B, global, unregister_name, [test]),
    ?UNTIL(undefined =:= global:whereis_name(test)),
    Pid = rpc:call(C, global, whereis_name, [test]),
    check_everywhere(Nodes--[C], test, Config),
    pong = rpc:call(B, net_adm, ping, [C]),

    %% Now the name has reappeared on node B.
    ?UNTIL(Pid =:= global:whereis_name(test)),
    check_everywhere(Nodes, test, Config),

    exit_p(Pid),

    ?UNTIL(undefined =:= global:whereis_name(test)),
    check_everywhere(Nodes, test, Config),

    write_high_level_trace(Config),
    stop_node(B),
    stop_node(C),
    init_condition(Config),
    ok.

lost_connection(Config) when is_list(Config) ->
    case prevent_overlapping_partitions() of
        true ->
            lost_connection_test(Config);
        false ->
            {skipped, "Prevent overlapping partitions disabled"}
    end.

lost_connection_test(Config) when is_list(Config) ->
    %% OTP-17843: Registered names could become inconsistent due to
    %%            overlapping partitions. This has been solved by
    %%            global actively disconnecting nodes to prevent
    %%            overlapping partitions.
    ct:timetrap({seconds, 15}),

    [Cp1, Cp2] = start_nodes([cp1, cp2], peer, Config),

    PartCtrlr = setup_partitions(Config, [[node(), Cp1, Cp2]]),

    wait_for_ready_net(Config),

    {Gurka, yes} = start_proc_basic(gurka),

    check_everywhere([node(), Cp1, Cp2], gurka, Config),

    Gurka = global:whereis_name(gurka),

    erlang:disconnect_node(Cp2), %% lost connection previously causing issues...

    erpc:call(
      PartCtrlr,
      fun () ->
              erpc:call(
                Cp2,
                fun () ->
                        {AltGurka, yes} = start_proc_basic(gurka),
                        AltGurka = global:whereis_name(gurka)
                end),
              timer:sleep(1000),
              erpc:cast(Cp2, erlang, halt, []),
              wait_until(fun () -> not lists:member(Cp2, nodes(hidden)) end)
      end),

    Reconnected = case lists:member(Cp1, nodes()) of
                      true ->
                          false;
                      false ->
                          erlang:display("reconnecting Cp1"),
                          pong = net_adm:ping(Cp1),
                          timer:sleep(500),
                          true
                  end,
    
    check_everywhere([node(), Cp1], gurka, Config),

    Gurka = global:whereis_name(gurka),

    ok = global:unregister_name(gurka),

    stop_node(Cp1),
    stop_partition_controller(PartCtrlr),

    {comment, case Reconnected of
                  true -> "Re-connected Cp1";
                  false -> "No re-connection of Cp1 needed"
              end}.

lost_connection2(Config) when is_list(Config) ->
    case prevent_overlapping_partitions() of
        true ->
            lost_connection2_test(Config);
        false ->
            {skipped, "Prevent overlapping partitions disabled"}
    end.

lost_connection2_test(Config) when is_list(Config) ->
    %% OTP-17843: Registered names could become inconsistent due to
    %%            overlapping partitions. This has been solved by
    %%            global actively disconnecting nodes to prevent
    %%            overlapping partitions.
    ct:timetrap({seconds, 15}),

    [Cp1, Cp2, Cp3, Cp4] = start_nodes([cp1, cp2, cp3, cp4], peer, Config),

    PartCtrlr = setup_partitions(Config, [[node(), Cp1, Cp2, Cp3, Cp4]]),

    wait_for_ready_net(Config),

    {Gurka, yes} = start_proc_basic(gurka),

    check_everywhere([node(), Cp1, Cp2], gurka, Config),

    Gurka = global:whereis_name(gurka),

    disconnect_nodes(PartCtrlr, Cp3, Cp4),

    Nodes = nodes(),
    true = lists:member(Cp1, Nodes),
    true = lists:member(Cp2, Nodes),
    false = lists:member(Cp3, Nodes),
    false = lists:member(Cp4, Nodes),

    pong = net_adm:ping(Cp3),
    pong = net_adm:ping(Cp4),

    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_partition_controller(PartCtrlr),

    ok.

-define(UNTIL_LOOP, 300).

-define(end_tag, 'end at').

init_high_level_trace(Time) ->
    Mul = try 
              test_server:timetrap_scale_factor()
	  catch _:_ -> 1
          end,
    put(?end_tag, msec() + Time * Mul * 1000),
    %% Assures that started nodes start the high level trace automatically.
    ok = gen_server:call(global_name_server, high_level_trace_start,infinity),
    os:putenv("GLOBAL_HIGH_LEVEL_TRACE", "TRUE"),
    put(?nodes_tag, []).

loop_until_true(Fun, Config, N) ->
    %% ?DBG([{n, N}]),
    put(n, N),
    case Fun() of
	true ->
	    true;
	_ ->
            case get(?end_tag) of
                undefined ->
                    timer:sleep(?UNTIL_LOOP),
                    loop_until_true(Fun, Config, N+1);
                EndAt ->
                    Left = EndAt - msec(),
                    case Left < 6000 of
                        true -> 
                            write_high_level_trace(Config),
                            Ref = make_ref(),
                            receive Ref -> ok end;
                        false ->
                            timer:sleep(?UNTIL_LOOP),
                            loop_until_true(Fun, Config, N+1)
                    end
            end
    end.

write_high_level_trace(Config) ->
    case erase(?nodes_tag) of
        undefined -> 
            ok;
        Nodes0 -> 
            Nodes = lists:usort([node() | Nodes0]),            
            write_high_level_trace(Nodes, Config)
    end.

write_high_level_trace(Nodes, Config) ->
    When = erlang:timestamp(),
    %% 'info' returns more than the trace, which is nice.
    Data = [{Node, {info, rpc:call(Node, global, info, [])}} ||
               Node <- Nodes],
    Dir = proplists:get_value(priv_dir, Config),
    DataFile = filename:join([Dir, lists:concat(["global_", ?testcase])]),
    io:format("\n\nAnalyze high level trace like this:\n"),
    io:format("global_trace:dd(~p, [{show_state, 0, 10}]). % 10 seconds\n",
             [DataFile]),
    file:write_file(DataFile, term_to_binary({high_level_trace, When, Data})).

lock_global2(Id, Parent) ->
    S = global:set_lock(Id),
    Parent ! {locked, S},
    receive
	{ok, Parent} ->
	    ok
    end.

%%-----------------------------------------------------------------
%% Test suite for global names and locks.
%% Should be started in a CC view with:
%% erl -sname XXX -rsh ctrsh where XX not in [cp1, cp2, cp3]
%%-----------------------------------------------------------------

%% cp1 - cp3 are started, and the name 'test' registered for a process on
%% test_server. Then it is checked that the name is registered on all
%% nodes, using whereis_name. Check that the same
%% name can't be registered with another value. Exit the registered
%% process and check that the name disappears. Register a new process
%% (Pid2) under the name 'test'. Let another new process (Pid3)
%% reregister itself under the same name. Test global:send/2. Test
%% unregister. Kill Pid3. Start a process (Pid6) on cp3,
%% register it as 'test', stop cp1 - cp3 and check that 'test' disappeared.
%% Kill Pid2 and check that 'test' isn't registered.

names(Config) when is_list(Config) ->
    ?TC_TRY(names, fun() -> do_names(Config) end).

do_names(Config) ->
    ?P("names -> begin when"
       "~n   Nodes: ~p"
       "~n   Names: ~p",
       [nodes(),
        case net_adm:names() of
            {ok, N} ->
                N;
            _ ->
                "-"
        end]),
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    ?P("names -> init high level trace"),
    init_high_level_trace(Timeout),
    ?P("names -> init condition"),
    init_condition(Config),
    ?P("names -> get registered names"),
    OrigNames = global:registered_names(),

    ?P("names -> start node cp1"),
    {ok, Cp1} = start_node(cp1, Config),
    ?P("names -> start node cp2"),
    {ok, Cp2} = start_node(cp2, Config),
    ?P("names -> start node cp3"),
    {ok, Cp3} = start_node(cp3, Config),

    ?P("names -> wait for ready net"),
    wait_for_ready_net(Config),

    %% start a proc and register it
    ?P("names -> start and register process 'test'"),
    {Pid, yes} = start_proc(test),

    %% test that it is registered at all nodes
    ?P("names -> verify process has been registered on all nodes"),
        ?UNTIL(begin
            (Pid =:= global:whereis_name(test)) and
            (Pid =:= rpc:call(Cp1, global, whereis_name, [test])) and
            (Pid =:= rpc:call(Cp2, global, whereis_name, [test])) and
            (Pid =:= rpc:call(Cp3, global, whereis_name, [test])) and
            ([test] =:= global:registered_names() -- OrigNames)
           end),
    
    %% try to register the same name
    ?P("names -> try register (locally) another 'test' (and expect rejection)"),
    no = global:register_name(test, self()),
    ?P("names -> try register (on cp1) another 'test' (and expect rejection)"),
    no = rpc:call(Cp1, global, register_name, [test, self()]),
    
    %% let process exit, check that it is unregistered automatically
    ?P("names -> terminate the 'test' process"),
    exit_p(Pid),

    ?P("names -> verify 'test' process has been automatically unregistered"),
        ?UNTIL((undefined =:= global:whereis_name(test)) and
           (undefined =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp3, global, whereis_name, [test]))),
    
    %% test re_register
    ?P("names -> start and register another process 'test'"),
    {Pid2, yes} = start_proc(test),
    ?P("names -> verify process 'test' has been registered"),
    ?UNTIL(Pid2 =:= rpc:call(Cp3, global, whereis_name, [test])),
    Pid3 = rpc:call(Cp3, ?MODULE, start_proc2, [test]),
    ?UNTIL(Pid3 =:= rpc:call(Cp3, global, whereis_name, [test])),
    Pid3 = global:whereis_name(test),

    %% test sending
    ?P("names -> test sending (from local)"),
    global:send(test, {ping, self()}),
    receive
	{pong, Cp3} -> ok
    after
	2000 -> ct:fail(timeout1)
    end,

    ?P("names -> test sending (from cp1)"),
    rpc:call(Cp1, global, send, [test, {ping, self()}]),
    receive
	{pong, Cp3} -> ok
    after
	2000 -> ct:fail(timeout2)
    end,

    ?P("names -> unregister 'test' process"),
    _ = global:unregister_name(test),
        ?UNTIL((undefined =:= global:whereis_name(test)) and
           (undefined =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp3, global, whereis_name, [test]))),

    ?P("names -> terminate process 'test'"),
    exit_p(Pid3),

    ?P("names -> verify not registered"),
    ?UNTIL(undefined =:= global:whereis_name(test)),

    %% register a proc
    ?P("names -> register a process"),
    {_Pid6, yes} = rpc:call(Cp3, ?MODULE, start_proc, [test]),

    ?P("names -> write high level trace"),
    write_high_level_trace(Config),

    %% stop the nodes, and make sure names are released.
    ?P("names -> stop node cp1"),
    stop_node(Cp1),
    ?P("names -> stop node cp2"),
    stop_node(Cp2),
    ?P("names -> stop node cp3"),
    stop_node(Cp3),

    ?P("names -> verify not registered"),
    ?UNTIL(undefined =:= global:whereis_name(test)),
    exit_p(Pid2),

    ?P("names -> verify not registered"),
    ?UNTIL(undefined =:= global:whereis_name(test)),
    init_condition(Config),

    ?P("names -> done"),
    ok.

%% Tests that names on a hidden node doesn't interfere with names on
%% visible nodes.
names_hidden(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),
    OrigNodes = nodes(),

    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),
    {ok, Cp3} = start_hidden_node(cp3, Config),
    pong = rpc:call(Cp1, net_adm, ping, [Cp3]),
    pong = rpc:call(Cp3, net_adm, ping, [Cp2]),
    pong = rpc:call(Cp3, net_adm, ping, [node()]),

    [] = [Cp1, Cp2 | OrigNodes] -- nodes(),

    %% start a proc on hidden node and register it
    {HPid, yes} = rpc:call(Cp3, ?MODULE, start_proc, [test]),
    Cp3 = node(HPid),

    %% Check that it didn't get registered on visible nodes
        ?UNTIL((undefined =:= global:whereis_name(test)) and
           (undefined =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp2, global, whereis_name, [test]))),

    %% start a proc on visible node and register it
    {Pid, yes} = start_proc(test),
    true = (Pid =/= HPid),

    %% test that it is registered at all nodes
        ?UNTIL((Pid =:= global:whereis_name(test)) and
           (Pid =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (Pid =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (HPid =:= rpc:call(Cp3, global, whereis_name, [test])) and
           ([test] =:= global:registered_names() -- OrigNames)),
    
    %% try to register the same name
    no = global:register_name(test, self()),
    no = rpc:call(Cp1, global, register_name, [test, self()]),
    
    %% let process exit, check that it is unregistered automatically
    exit_p(Pid),

        ?UNTIL((undefined =:= global:whereis_name(test)) and
           (undefined =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (HPid      =:= rpc:call(Cp3, global, whereis_name, [test]))),
    
    %% test re_register
    {Pid2, yes} = start_proc(test),
    ?UNTIL(Pid2 =:= rpc:call(Cp2, global, whereis_name, [test])),
    Pid3 = rpc:call(Cp2, ?MODULE, start_proc2, [test]),
    ?UNTIL(Pid3 =:= rpc:call(Cp2, global, whereis_name, [test])),
    Pid3 = global:whereis_name(test),

    %% test sending
    Pid3 = global:send(test, {ping, self()}),
    receive
	{pong, Cp2} -> ok
    after
	2000 -> ct:fail(timeout1)
    end,

    rpc:call(Cp1, global, send, [test, {ping, self()}]),
    receive
	{pong, Cp2} -> ok
    after
	2000 -> ct:fail(timeout2)
    end,

    _ = rpc:call(Cp3, global, unregister_name, [test]),
        ?UNTIL((Pid3      =:= global:whereis_name(test)) and
           (Pid3      =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (Pid3      =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp3, global, whereis_name, [test]))),

    _ = global:unregister_name(test),
        ?UNTIL((undefined =:= global:whereis_name(test)) and
           (undefined =:= rpc:call(Cp1, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp2, global, whereis_name, [test])) and
           (undefined =:= rpc:call(Cp3, global, whereis_name, [test]))),

    exit_p(Pid3),
    exit_p(HPid),

    ?UNTIL(undefined =:= global:whereis_name(test)),

    write_high_level_trace(Config),

    %% stop the nodes, and make sure names are released.
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),

    init_condition(Config),
    ok.

locks(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),
    {ok, Cp3} = start_node(cp3, Config),

    wait_for_ready_net(Config),

    %% start two procs
    Pid = start_proc(),
    Pid2 = rpc:call(Cp1, ?MODULE, start_proc, []),

    %% set a lock, and make sure no one else can set the same lock
    true = global:set_lock({test_lock, self()}, ?NODES, 1),
    false = req(Pid, {set_lock, test_lock, self()}),
    false = req(Pid2, {set_lock, test_lock, self()}),

    %% delete, and let another proc set the lock
    global:del_lock({test_lock, self()}),
    true = req(Pid, {set_lock, test_lock, self()}),
    false = req(Pid2, {set_lock, test_lock, self()}),
    false = global:set_lock({test_lock, self()}, ?NODES,1),

    %% kill lock-holding proc, make sure the lock is released
    exit_p(Pid),
    ?UNTIL(true =:= global:set_lock({test_lock, self()}, ?NODES,1)),
    Pid2 ! {set_lock_loop, test_lock, self()},

    %% make sure we don't have the msg
    receive
	{got_lock, Pid2} -> ct:fail(got_lock)
    after
	1000 -> ok
    end,
    global:del_lock({test_lock, self()}),

    %% make sure pid2 got the lock
    receive
	{got_lock, Pid2} -> ok
    after
	%% 12000 >> 5000, which is the max time before a new retry for
        %% set_lock
	12000 -> ct:fail(got_lock2)
    end,

    %% let proc set the same lock
    true = req(Pid2, {set_lock, test_lock, self()}),

    %% let proc set new lock
    true = req(Pid2, {set_lock, test_lock2, self()}),
    false = global:set_lock({test_lock, self()},?NODES,1),
    false = global:set_lock({test_lock2, self()}, ?NODES,1),
    exit_p(Pid2),
    ?UNTIL(true =:= global:set_lock({test_lock, self()}, ?NODES, 1)),
    ?UNTIL(true =:= global:set_lock({test_lock2, self()}, ?NODES, 1)),
    global:del_lock({test_lock, self()}),
    global:del_lock({test_lock2, self()}),

    %% let proc set two locks
    Pid3 = rpc:call(Cp1, ?MODULE, start_proc, []),
    true = req(Pid3, {set_lock, test_lock, self()}),
    true = req(Pid3, {set_lock, test_lock2, self()}),

    %% del one lock
    Pid3 ! {del_lock, test_lock2},
    ct:sleep(100),

    %% check that one lock is still set, but not the other
    false = global:set_lock({test_lock, self()}, ?NODES, 1),
    true = global:set_lock({test_lock2, self()}, ?NODES, 1),
    global:del_lock({test_lock2, self()}),

    %% kill lock-holder
    exit_p(Pid3),

    ?UNTIL(true =:= global:set_lock({test_lock, self()}, ?NODES, 1)),
    global:del_lock({test_lock, self()}),
    ?UNTIL(true =:= global:set_lock({test_lock2, self()}, ?NODES, 1)),
    global:del_lock({test_lock2, self()}),

    %% start one proc on each node
    Pid4 = start_proc(),
    Pid5 = rpc:call(Cp1, ?MODULE, start_proc, []),
    Pid6 = rpc:call(Cp2, ?MODULE, start_proc, []),
    Pid7 = rpc:call(Cp3, ?MODULE, start_proc, []),

    %% set lock on two nodes
    true = req(Pid4, {set_lock, test_lock, self(), [node(), Cp1]}),
    false = req(Pid5, {set_lock, test_lock, self(), [node(), Cp1]}),

    %% set same lock on other two nodes
    true = req(Pid6, {set_lock, test_lock, self(), [Cp2, Cp3]}),
    false = req(Pid7, {set_lock, test_lock, self(), [Cp2, Cp3]}),

    %% release lock
    Pid6 ! {del_lock, test_lock, [Cp2, Cp3]},

    %% try to set lock on a node that already has the lock
    false = req(Pid6, {set_lock, test_lock, self(), [Cp1, Cp2, Cp3]}),

    %% set lock on a node
    exit_p(Pid4),
    ?UNTIL(true =:= req(Pid5, {set_lock, test_lock, self(), [node(), Cp1]})),
    Pid8 = start_proc(),
    false = req(Pid8, {set_lock, test_lock, self()}),
    write_high_level_trace(Config),

    %% stop the nodes, and make sure locks are released.
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    ct:sleep(100),
    true = req(Pid8, {set_lock, test_lock, self()}),
    exit_p(Pid8),
    ct:sleep(10),

    init_condition(Config),
    ok.


%% Tests that locks on a hidden node doesn't interere with locks on
%% visible nodes.
locks_hidden(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNodes = nodes(),
    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),
    {ok, Cp3} = start_hidden_node(cp3, Config),
    pong = rpc:call(Cp1, net_adm, ping, [Cp3]),
    pong = rpc:call(Cp3, net_adm, ping, [Cp2]),
    pong = rpc:call(Cp3, net_adm, ping, [node()]),

    [] = [Cp1, Cp2 | OrigNodes] -- nodes(),

    %% start two procs
    Pid = start_proc(),
    Pid2 = rpc:call(Cp1, ?MODULE, start_proc, []),
    HPid = rpc:call(Cp3, ?MODULE, start_proc, []),

    %% Make sure hidden node doesn't interfere with visible nodes lock
    true = req(HPid, {set_lock, test_lock, self()}),
    true = global:set_lock({test_lock, self()}, ?NODES, 1),
    false = req(Pid, {set_lock, test_lock, self()}),
    true = req(HPid, {del_lock_sync, test_lock, self()}),
    false = req(Pid2, {set_lock, test_lock, self()}),

    %% delete, and let another proc set the lock
    global:del_lock({test_lock, self()}),
    true = req(Pid, {set_lock, test_lock, self()}),
    false = req(Pid2, {set_lock, test_lock, self()}),
    false = global:set_lock({test_lock, self()}, ?NODES,1),

    %% kill lock-holding proc, make sure the lock is released
    exit_p(Pid),
    ?UNTIL(true =:= global:set_lock({test_lock, self()}, ?NODES, 1)),
    ?UNTIL(true =:= req(HPid, {set_lock, test_lock, self()})),
    Pid2 ! {set_lock_loop, test_lock, self()},

    %% make sure we don't have the msg
    receive
	{got_lock, Pid2} -> ct:fail(got_lock)
    after
	1000 -> ok
    end,
    global:del_lock({test_lock, self()}),

    %% make sure pid2 got the lock
    receive
	{got_lock, Pid2} -> ok
    after
	%% 12000 >> 5000, which is the max time before a new retry for
        %% set_lock
	12000 -> ct:fail(got_lock2)
    end,
    true = req(HPid, {del_lock_sync, test_lock, self()}),

    %% let proc set the same lock
    true = req(Pid2, {set_lock, test_lock, self()}),

    %% let proc set new lock
    true = req(Pid2, {set_lock, test_lock2, self()}),
    true = req(HPid, {set_lock, test_lock, self()}),
    true = req(HPid, {set_lock, test_lock2, self()}),
    exit_p(HPid),
    false = global:set_lock({test_lock, self()},?NODES,1),
    false = global:set_lock({test_lock2, self()}, ?NODES,1),

    exit_p(Pid2),
    ?UNTIL(true =:= global:set_lock({test_lock, self()}, ?NODES, 1)),
    ?UNTIL(true =:= global:set_lock({test_lock2, self()}, ?NODES, 1)),
    global:del_lock({test_lock, self()}),
    global:del_lock({test_lock2, self()}),

    write_high_level_trace(Config),

    %% stop the nodes, and make sure locks are released.
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),

    init_condition(Config),
    ok.


bad_input(Config) when is_list(Config) ->
    Timeout = 15,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    Pid = whereis(global_name_server),
    {'EXIT', _} = (catch global:set_lock(bad_id)),
    {'EXIT', _} = (catch global:set_lock({id, self()}, bad_nodes)),
    {'EXIT', _} = (catch global:del_lock(bad_id)),
    {'EXIT', _} = (catch global:del_lock({id, self()}, bad_nodes)),
    {'EXIT', _} = (catch global:register_name(name, bad_pid)),
    {'EXIT', _} = (catch global:reregister_name(name, bad_pid)),
    {'EXIT', _} = (catch global:trans(bad_id, {m,f})),
    {'EXIT', _} = (catch global:trans({id, self()}, {m,f}, [node()], -1)),
    Pid = whereis(global_name_server),
    init_condition(Config),
    ok.

names_and_locks(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),
    {ok, Cp3} = start_node(cp3, Config),

    %% start one proc on each node
    PidTS = start_proc(),
    Pid1 = rpc:call(Cp1, ?MODULE, start_proc, []),
    Pid2 = rpc:call(Cp2, ?MODULE, start_proc, []),
    Pid3 = rpc:call(Cp3, ?MODULE, start_proc, []),

    %% register some of them
    yes = global:register_name(test1, Pid1),
    yes = global:register_name(test2, Pid2),
    yes = global:register_name(test3, Pid3),
    no = global:register_name(test3, PidTS),
    yes = global:register_name(test4, PidTS),

    %% set lock on two nodes
    true = req(PidTS, {set_lock, test_lock, self(), [node(), Cp1]}),
    false = req(Pid1, {set_lock, test_lock, self(), [node(), Cp1]}),

    %% set same lock on other two nodes
    true = req(Pid2, {set_lock, test_lock, self(), [Cp2, Cp3]}),
    false = req(Pid3, {set_lock, test_lock, self(), [Cp2, Cp3]}),

    %% release lock
    Pid2 ! {del_lock, test_lock, [Cp2, Cp3]},
    ct:sleep(100),

    %% try to set lock on a node that already has the lock
    false = req(Pid2, {set_lock, test_lock, self(), [Cp1, Cp2, Cp3]}),

    %% set two locks
    true = req(Pid2, {set_lock, test_lock, self(), [Cp2, Cp3]}),
    true = req(Pid2, {set_lock, test_lock2, self(), [Cp2, Cp3]}),

    %% kill some processes, make sure all locks/names are released
    exit_p(PidTS),
    ?UNTIL(undefined =:= global:whereis_name(test4)),
    true = global:set_lock({test_lock, self()}, [node(), Cp1], 1),
    global:del_lock({test_lock, self()}, [node(), Cp1]),
    
    exit_p(Pid2),
        ?UNTIL((undefined =:= global:whereis_name(test2)) and
           (true =:= global:set_lock({test_lock, self()}, [Cp2, Cp3], 1)) and
           (true =:= global:set_lock({test_lock2, self()}, [Cp2, Cp3], 1))),

    global:del_lock({test_lock, self()}, [Cp2, Cp3]),
    global:del_lock({test_lock2, self()}, [Cp2, Cp3]),

    exit_p(Pid1),
    exit_p(Pid3),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),

    init_condition(Config),
    ok.

%% OTP-6341. Remove locks using monitors.
lock_die(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),

    %% First test.
    LockId = {id, self()},
    Pid2 = start_proc(),
    true = req(Pid2, {set_lock2, LockId, self()}),

    true = global:set_lock(LockId, [Cp1]),
    %% Id is locked on Cp1 and Cp2 (by Pid2) but not by self(): 
    %% (there is no mon. ref)
    _ = global:del_lock(LockId, [node(), Cp1, Cp2]),

    exit_p(Pid2),

    %% Second test.
    Pid3 = start_proc(),
    true = req(Pid3, {set_lock, id, self(), [Cp1]}),
    %% The lock is removed from Cp1 thanks to monitors.
    exit_p(Pid3),

    true = global:set_lock(LockId, [node(), Cp1]),
    _ = global:del_lock(LockId, [node(), Cp1]),

    ?UNTIL(OrigNames =:= global:registered_names()),
    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    init_condition(Config),
    ok.

%% OTP-6341. Remove names using monitors.
name_die(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),
    [Cp1] = Cps = start_nodes([z], peer,  Config), % z > test_server
    Nodes = lists:sort([node() | Cps]),
    wait_for_ready_net(Config),

    Name = name_die,
    Pid = rpc:call(Cp1, ?MODULE, start_proc, []),

    %% Test 1. No resolver is called if the same pid is registered on
    %% both partitions.
    T1 = node(),
    Part1 = [T1],
    Part2 = [Cp1],

    PartCtrlr = setup_partitions(Config, [Part1, Part2]),

    ?UNTIL(undefined =:= global:whereis_name(Name)),
    yes = global:register_name(Name, Pid),

    pong = net_adm:ping(Cp1),
    wait_for_ready_net(Nodes, Config),
    assert_pid(global:whereis_name(Name)),
    exit_p(Pid),
    ?UNTIL(OrigNames =:= global:registered_names()),

    %% Test 2. Register a name running outside the current partition.
    %% Killing the pid will not remove the name from the current
    %% partition, unless monitors are used.
    Pid2 = rpc:call(Cp1, ?MODULE, start_proc, []),
    Dir = proplists:get_value(priv_dir, Config),
    KillFile = filename:join([Dir, "kill.txt"]),
    file:delete(KillFile),
    erlang:spawn(Cp1, fun() -> kill_pid(Pid2, KillFile, Config) end),

    setup_partitions(PartCtrlr, [Part1, Part2]),

    ?UNTIL(undefined =:= global:whereis_name(Name)),
    yes = global:register_name(Name, Pid2),
    touch(KillFile, "kill"),
    file_contents(KillFile, "done", Config),
    file:delete(KillFile),

    ?UNTIL(OrigNames =:= global:registered_names()),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

kill_pid(Pid, File, Config) ->
    file_contents(File, "kill", Config),
    exit_p(Pid),
    touch(File, "done").

%% Tests that two partitioned networks exchange correct info.
basic_partition(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [Cp1, Cp2, Cp3] = start_nodes([cp1, cp2, cp3], peer, Config),
    [Cp1, Cp2, Cp3] = lists:sort(nodes()),

    wait_for_ready_net(Config),

    %% make cp2 and cp3 connected, partitioned from us and cp1
    PCtrlr = setup_partitions(Config, [[node(), Cp1], [Cp2, Cp3]]),

    %% start different processes in both partitions
    {Pid, yes} = start_proc(test),

    %% Reach into the other partition via PCtrlr...
    ok = erpc:call(
           PCtrlr,
           fun () ->
                   {_, yes} = erpc:call(Cp2, ?MODULE,
                                        start_proc, [test2]),
                   {_, yes} = erpc:call(Cp1, ?MODULE,
                                        start_proc, [test4]),
                   ok
           end),

    %% connect to other partition
    pong = net_adm:ping(Cp2),
    pong = net_adm:ping(Cp3),
    wait_until(fun () -> [Cp1, Cp2, Cp3] == lists:sort(nodes()) end),

    %% check names
    ?UNTIL(Pid =:= rpc:call(Cp2, global, whereis_name, [test])),
    ?UNTIL(undefined =/= global:whereis_name(test2)),
    Pid2 = global:whereis_name(test2),
    Pid2 = rpc:call(Cp2, global, whereis_name, [test2]),
    assert_pid(Pid2),
    Pid3 = global:whereis_name(test4),
    ?UNTIL(Pid3 =:= rpc:call(Cp1, global, whereis_name, [test4])),
    assert_pid(Pid3),

    %% kill all procs
    Pid3 = global:send(test4, die),
    %% sleep to let the proc die
    wait_for_exit(Pid3),
    ?UNTIL(undefined =:= global:whereis_name(test4)),

    exit_p(Pid),
    exit_p(Pid2),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(PCtrlr),
    init_condition(Config),
    ok.

%% Creates two partitions with two nodes in each partition.
%% Tests that names are exchanged correctly, and that EXITs
%% during connect phase are handled correctly.
basic_name_partition(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [Cp1, Cp2, Cp3] = start_nodes([cp1, cp2, cp3], peer, Config),
    [Cp1, Cp2, Cp3] = lists:sort(nodes()),
    Nodes = ?NODES,

    wait_for_ready_net(Config),

    %% There used to be more than one name registered for some
    %% processes. That was a mistake; there is no support for more than
    %% one name per process, and the manual is quite clear about that
    %% ("equivalent to the register/2 and whereis/1 BIFs"). The
    %% resolver procedure did not take care of such "duplicated" names,
    %% which caused this testcase to fail every now and then.

    %% make cp2 and cp3 connected, partitioned from us and cp1
    %% us:  register name03
    %% cp1: register name12
    %% cp2: register name12
    %% cp3: register name03

    PCtrlr = setup_partitions(Config, [[node(), Cp1], [Cp2, Cp3]]),

    %% start different processes in both partitions
    {_, yes} = start_proc_basic(name03),
    {_, yes} = erpc:call(Cp1, ?MODULE, start_proc_basic, [name12]),

    %% Reach into the other partition via PCtrlr...
    ok = erpc:call(
           PCtrlr,
           fun () ->
                   {_, yes} = erpc:call(Cp2, ?MODULE,
                                        start_proc_basic, [name12]),
                   {_, yes} = erpc:call(Cp3, ?MODULE,
                                        start_proc_basic, [name03]),
                   ok
           end),

    ct:sleep(1000),

    %% connect to other partition
    pong = net_adm:ping(Cp3),

    ?UNTIL([Cp1, Cp2, Cp3] =:= lists:sort(nodes())),
    wait_for_ready_net(Config),

    %% check names
    Pid03 = global:whereis_name(name03),
    assert_pid(Pid03),
    true = lists:member(node(Pid03), [node(), Cp3]),
    check_everywhere(Nodes, name03, Config),

    Pid12 = global:whereis_name(name12),
    assert_pid(Pid12),
    true = lists:member(node(Pid12), [Cp1, Cp2]),
    check_everywhere(Nodes, name12, Config),

    %% kill all procs
    Pid12 = global:send(name12, die),
    Pid03 = global:send(name03, die),

    %% sleep to let the procs die
    wait_for_exit(Pid12),
    wait_for_exit(Pid03),
    ?UNTIL(begin
	       Names = [name03, name12],
	       lists:duplicate(length(Names), undefined)
		   =:= [global:whereis_name(Name) || Name <- Names]
	   end),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(PCtrlr),
    init_condition(Config),
    ok.

%% Peer nodes cp0 - cp6 are started. Break apart the connections from
%% cp3-cp6 to cp0-cp2 and test_server so we get two partitions.
%% In the cp3-cp6 partition, start one process on each node and register
%% using both erlang:register, and global:register (test1 on cp3, test2 on
%% cp4, test3 on cp5, test4 on cp6), using different resolution functions:
%% default for test1, notify_all_name for test2, random_notify_name for test3
%% and one for test4 that sends a message to test_server and keeps the
%% process which is greater in the standard ordering. In the other partition,
%% do the same (test1 on test_server, test2 on cp0, test3 on cp1, test4 on cp2).
%% Sleep a little, then from test_server, connect to cp3-cp6 in order.
%% Check that the values for the registered names are the expected ones, and
%% that the messages from test4 arrive.

%% Test that names are resolved correctly when two
%% partitioned networks connect.
advanced_partition(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    Parent = self(),

    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6]
	= start_nodes([cp0, cp1, cp2, cp3, cp4, cp5, cp6], peer, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6]),
    wait_for_ready_net(Config),

    %% make cp3-cp6 connected, partitioned from us and cp0-cp2
    PCntrlr = setup_partitions(Config, [[node(), Cp0, Cp1, Cp2], [Cp3, Cp4, Cp5, Cp6]]),

    %% start processes in other partition (via partition controller)...
    _ = erpc:call(PCntrlr,
                  fun () ->
                          erpc:call(Cp3,
                                    fun () ->
                                            start_procs(Parent, Cp4, Cp5, Cp6, Config)
                                    end)
                  end),

    %% start different processes in this partition
    start_procs(self(), Cp0, Cp1, Cp2, Config),

    %% connect to other partition
    pong = net_adm:ping(Cp3),

    wait_until(fun () ->
                       CurrNodes = lists:sort(?NODES),
                       io:format("CurrNodes: ~p~n", [CurrNodes]),
                       Nodes == CurrNodes end),

    wait_for_ready_net(Config),

    ?UNTIL(lists:member(undefined,
			[rpc:call(Cp3, erlang, whereis, [test1]),
			 rpc:call(node(), erlang, whereis, [test1])])),

    Nt1 = rpc:call(Cp3, erlang, whereis, [test1]),
    Nt2 = rpc:call(Cp4, erlang, whereis, [test2]),
    Nt3 = rpc:call(Cp5, erlang, whereis, [test3]),
    Nt4 = rpc:call(Cp6, erlang, whereis, [test4]),

    Mt1 = rpc:call(node(), erlang, whereis, [test1]),
    Mt2 = rpc:call(Cp0, erlang, whereis, [test2]),
    Mt3 = rpc:call(Cp1, erlang, whereis, [test3]),
    _Mt4 = rpc:call(Cp2, erlang, whereis, [test4]),

    %% check names
    Pid1 = global:whereis_name(test1),
    Pid1 = rpc:call(Cp3, global, whereis_name, [test1]),
    assert_pid(Pid1),
    true = lists:member(Pid1, [Nt1, Mt1]),
    true = lists:member(undefined, [Nt1, Mt1]),
    check_everywhere(Nodes, test1, Config),

    undefined = global:whereis_name(test2),
    undefined = rpc:call(Cp3, global, whereis_name, [test2]),
    yes = sreq(Nt2, {got_notify, self()}),
    yes = sreq(Mt2, {got_notify, self()}),
    check_everywhere(Nodes, test2, Config),

    Pid3 = global:whereis_name(test3),
    Pid3 = rpc:call(Cp3, global, whereis_name, [test3]),
    assert_pid(Pid3),
    true = lists:member(Pid3, [Nt3, Mt3]),
    no = sreq(Pid3, {got_notify, self()}),
    yes = sreq(other(Pid3, [Nt2, Nt3]), {got_notify, self()}),
    check_everywhere(Nodes, test3, Config),

    Pid4 = global:whereis_name(test4),
    Pid4 = rpc:call(Cp3, global, whereis_name, [test4]),
    assert_pid(Pid4),
    Pid4 = Nt4,
    check_everywhere(Nodes, test4, Config),

    1 = collect_resolves(),

    Pid1 = global:send(test1, die),
    exit_p(Pid3),
    exit_p(Pid4),
    wait_for_exit(Pid1),
    wait_for_exit(Pid3),
    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_node(Cp6),
    stop_node(PCntrlr),
    init_condition(Config),
    ok.

%% Peer nodes cp0 - cp6 are started, and partitioned just like in
%% advanced_partition. Start cp8, only connected to test_server. Let cp6
%% break apart from the rest, and 12 s later, ping cp0 and cp3, and
%% register the name test5. After the same 12 s, let cp5 halt.
%% Wait for the death of cp5. Ping cp3 (at the same time as cp6 does).
%% Take down cp2. Start cp7, restart cp2. Ping cp4, cp6 and cp8.
%% Now, expect all nodes to be connected and have the same picture of all
%% registered names.

%% Stress global, make a partitioned net, make some nodes
%% go up/down a bit.
stress_partition(Config) when is_list(Config) ->
    Timeout = 90,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    Parent = self(),

    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6a, Cp6b]
	= start_nodes([cp0, cp1, cp2, cp3, cp4, cp5, cp6a, cp6b], peer, Config),

    wait_for_ready_net(Config),

    %% make cp3-cp5 connected, partitioned from us and cp0-cp2
    %% cp6 is alone (single node).  cp6 pings cp0 and cp3 in 12 secs...
    PCntrlr = setup_partitions(Config, [[node(), Cp0, Cp1, Cp2], [Cp3, Cp4, Cp5, Cp6a], [Cp6b]]),

    %% start processes in other partition (via partition controller)...
    _ = erpc:call(PCntrlr,
                  fun () ->
                          erpc:call(Cp3,
                                    fun () ->
                                            start_procs(Parent, Cp4, Cp5, Cp6a, Config)
                                    end),
                          erpc:call(Cp6b,
                                    fun () ->
                                            Pid1 = start_proc3(test1),
                                            assert_pid(Pid1),
                                            Pid2 = start_proc3(test3),
                                            assert_pid(Pid2),
                                            yes = global:register_name(
                                                    test1, Pid1),
                                            yes = global:register_name(
                                                    test3, Pid2,
                                                    fun global:random_notify_name/3)
                                    end),
                          %% Make Cp5 crash
                          erpc:cast(Cp5, ?MODULE, crash, [12000]),
                          %% Make Cp6b alone
                          erpc:cast(Cp6b, ?MODULE, alone, [Cp0, Cp3])
                  end),

    erlang:display(starting_test),
    %% start different processes in this partition
    start_procs(self(), Cp0, Cp1, Cp2, Config),

    {ok, Cp8} = start_peer_node(cp8, Config),

    monitor_node(Cp5, true),
    receive
	{nodedown, Cp5} -> ok
    after
	20000 -> ct:fail({no_nodedown, Cp5})
    end,
    monitor_node(Cp5, false),    

    %% Ok, now cp6 pings us, and cp5 will go down.

    %% connect to other partition
    pong = net_adm:ping(Cp3),
    pong = net_adm:ping(Cp4),
    rpc_cast(Cp2, ?MODULE, crash, [0]),

    %% Start new nodes
    {ok, Cp7} = start_peer_node(cp7, Config),
    {ok, Cp2_2} = start_peer_node(cp2, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2_2, Cp3, Cp4, Cp6a, Cp6b, Cp7, Cp8]),
    put(?nodes_tag, Nodes),

    %% We don't know how the crashes partitions the net, so
    %% we cast trough all nodes so we get them all connected
    %% again...
    cast_line(Nodes),

    wait_for_ready_net(Nodes, Config),

    %% Make sure that all nodes have the same picture of all names
    check_everywhere(Nodes, test1, Config),
    assert_pid(global:whereis_name(test1)),

    check_everywhere(Nodes, test2, Config),
    undefined = global:whereis_name(test2),

    check_everywhere(Nodes, test3, Config),
    assert_pid(global:whereis_name(test3)),

    check_everywhere(Nodes, test4, Config),
    assert_pid(global:whereis_name(test4)),

    check_everywhere(Nodes, test5, Config),
    ?UNTIL(undefined =:= global:whereis_name(test5)),

    assert_pid(global:send(test1, die)),
    assert_pid(global:send(test3, die)),
    assert_pid(global:send(test4, die)),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2_2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_node(Cp6a),
    stop_node(Cp6b),
    stop_node(Cp7),
    stop_node(Cp8),
    stop_node(PCntrlr),
    init_condition(Config),
    ok.


%% Use this one to test a lot of connection tests
%%  erl -sname ts -ring_line 10000 -s test_server run_test global_SUITE

ring_line(Config) when is_list(Config) ->
    {ok, [[N]]} = init:get_argument(ring_line),
    loop_it(list_to_integer(N), Config).

loop_it(N, Config) -> loop_it(N,N, Config).

loop_it(0,_, _Config) -> ok;
loop_it(N,M, Config) ->
    ct:pal(?HI_VERBOSITY, "Round: ~w", [M-N]),
    ring(Config),
    line(Config),
    loop_it(N-1,M, Config).


%% Make 10 single nodes, all having the same name.
%% Make all ping its predecessor, pinging in a ring.
%% Make sure that there's just one winner.
ring(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6, Cp7, Cp8]
	= start_nodes([cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8], 
                      peer, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6, Cp7, Cp8]),

    wait_for_ready_net(Config),

    PartCtrlr = setup_partitions(Config,
                                 [[node()], [Cp0], [Cp1], [Cp2], [Cp3],
                                  [Cp4], [Cp5], [Cp6], [Cp7], [Cp8]]),

    Time = msec() + 1000,

    ok = erpc:call(
           PartCtrlr,
           fun () ->
                   erpc:cast(Cp0, ?MODULE, single_node, [Time, Cp8]), % ping ourself!
                   erpc:cast(Cp1, ?MODULE, single_node, [Time, Cp0]),
                   erpc:cast(Cp2, ?MODULE, single_node, [Time, Cp1]),
                   erpc:cast(Cp3, ?MODULE, single_node, [Time, Cp2]),
                   erpc:cast(Cp4, ?MODULE, single_node, [Time, Cp3]),
                   erpc:cast(Cp5, ?MODULE, single_node, [Time, Cp4]),
                   erpc:cast(Cp6, ?MODULE, single_node, [Time, Cp5]),
                   erpc:cast(Cp7, ?MODULE, single_node, [Time, Cp6]),
                   erpc:cast(Cp8, ?MODULE, single_node, [Time, Cp7]),
                   ok
           end),

    pong = net_adm:ping(Cp0),

    wait_for_ready_net(Nodes, Config),

    %% Just make sure that all nodes have the same picture of all names
    check_everywhere(Nodes, single_name, Config),
    assert_pid(global:whereis_name(single_name)),

    ?UNTIL(begin
               {Ns2, []} = rpc:multicall(Nodes, erlang, whereis, 
                                         [single_name]),
               9 =:= lists:foldl(fun(undefined, N) -> N + 1;
                                    (_, N) -> N
                                 end,
                                 0, Ns2)
           end),

    assert_pid(global:send(single_name, die)),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_node(Cp6),
    stop_node(Cp7),
    stop_node(Cp8),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% Simpler version of the ring case.  Used because there are some
%% distribution problems with many nodes.
%% Make 6 single nodes, all having the same name.
%% Make all ping its predecessor, pinging in a ring.
%% Make sure that there's just one winner.
simple_ring(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    Names = [cp0, cp1, cp2, cp3, cp4, cp5],
    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5]
	= start_nodes(Names, peer, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2, Cp3, Cp4, Cp5]),

    wait_for_ready_net(Config),

    PartCtrlr = setup_partitions(Config,
                                 [[node()], [Cp0], [Cp1], [Cp2], [Cp3],
                                  [Cp4], [Cp5]]),
    Time = msec() + 1000,

    ok = erpc:call(
           PartCtrlr,
           fun () ->
                   erpc:cast(Cp0, ?MODULE, single_node, [Time, Cp5]), % ping ourself!
                   erpc:cast(Cp1, ?MODULE, single_node, [Time, Cp0]),
                   erpc:cast(Cp2, ?MODULE, single_node, [Time, Cp1]),
                   erpc:cast(Cp3, ?MODULE, single_node, [Time, Cp2]),
                   erpc:cast(Cp4, ?MODULE, single_node, [Time, Cp3]),
                   erpc:cast(Cp5, ?MODULE, single_node, [Time, Cp4]),
                   ok
           end),

    pong = net_adm:ping(Cp0),

    wait_for_ready_net(Nodes, Config),

    %% Just make sure that all nodes have the same picture of all names
    check_everywhere(Nodes, single_name, Config),
    assert_pid(global:whereis_name(single_name)),

    ?UNTIL(begin
               {Ns2, []} = rpc:multicall(Nodes, erlang, whereis, 
                                         [single_name]),
               6 =:= lists:foldl(fun(undefined, N) -> N + 1;
                                    (_, N) -> N
                                 end,
                                 0, Ns2)
           end),

    assert_pid(global:send(single_name, die)),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% Make 6 single nodes, all having the same name.
%% Make all ping its predecessor, pinging in a line.
%% Make sure that there's just one winner.
line(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6, Cp7, Cp8]
	= start_nodes([cp0, cp1, cp2, cp3, cp4, cp5, cp6, cp7, cp8], 
                      peer, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2, Cp3, Cp4, Cp5, Cp6, Cp7, Cp8]),

    wait_for_ready_net(Config),

    PartCtrlr = setup_partitions(Config,
                                 [[node()], [Cp0], [Cp1], [Cp2], [Cp3],
                                  [Cp4], [Cp5], [Cp6], [Cp7], [Cp8]]),
    ThisNode = node(),

    Time = msec() + 1000,
    ok = erpc:call(
           PartCtrlr,
           fun () ->
                   erpc:cast(Cp0, ?MODULE, single_node, [Time, Cp0]), % ping ourself!
                   erpc:cast(Cp1, ?MODULE, single_node, [Time, Cp0]),
                   erpc:cast(Cp2, ?MODULE, single_node, [Time, Cp1]),
                   erpc:cast(Cp3, ?MODULE, single_node, [Time, Cp2]),
                   erpc:cast(Cp4, ?MODULE, single_node, [Time, Cp3]),
                   erpc:cast(Cp5, ?MODULE, single_node, [Time, Cp4]),
                   erpc:cast(Cp6, ?MODULE, single_node, [Time, Cp5]),
                   erpc:cast(Cp7, ?MODULE, single_node, [Time, Cp6]),
                   erpc:cast(Cp8, ?MODULE, single_node, [Time, Cp7]),
                   erpc:cast(ThisNode, ?MODULE, single_node, [Time, Cp8]),
                   ok
           end),

    wait_for_ready_net(Nodes, Config),

    %% Just make sure that all nodes have the same picture of all names
    check_everywhere(Nodes, single_name, Config),
    assert_pid(global:whereis_name(single_name)),

    ?UNTIL(begin
	       {Ns2, []} = rpc:multicall(Nodes, erlang, whereis,
					 [single_name]),
 	       9 =:= lists:foldl(fun(undefined, N) -> N + 1;
                                    (_, N) -> N
                                 end,
                                 0, Ns2)
	   end),

    assert_pid(global:send(single_name, die)),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_node(Cp6),
    stop_node(Cp7),
    stop_node(Cp8),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.


%% Simpler version of the line case.  Used because there are some
%% distribution problems with many nodes.
%% Make 6 single nodes, all having the same name.
%% Make all ping its predecessor, pinging in a line.
%% Make sure that there's just one winner.
simple_line(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [Cp0, Cp1, Cp2, Cp3, Cp4, Cp5]
	= start_nodes([cp0, cp1, cp2, cp3, cp4, cp5], peer, Config),
    Nodes = lists:sort([node(), Cp0, Cp1, Cp2, Cp3, Cp4, Cp5]),

    wait_for_ready_net(Config),

    PartCtrlr = setup_partitions(Config,
                                 [[node()], [Cp0], [Cp1], [Cp2], [Cp3],
                                  [Cp4], [Cp5]]),
    ThisNode = node(),

    Time = msec() + 1000,
    ok = erpc:call(
           PartCtrlr,
           fun () ->
                   erpc:cast(Cp0, ?MODULE, single_node, [Time, Cp0]), % ping ourself!
                   erpc:cast(Cp1, ?MODULE, single_node, [Time, Cp0]),
                   erpc:cast(Cp2, ?MODULE, single_node, [Time, Cp1]),
                   erpc:cast(Cp3, ?MODULE, single_node, [Time, Cp2]),
                   erpc:cast(Cp4, ?MODULE, single_node, [Time, Cp3]),
                   erpc:cast(Cp5, ?MODULE, single_node, [Time, Cp4]),
                   erpc:cast(ThisNode, ?MODULE, single_node, [Time, Cp5]),
                   ok
           end),

    wait_for_ready_net(Nodes, Config),

    %% Just make sure that all nodes have the same picture of all names
    check_everywhere(Nodes, single_name, Config),
    assert_pid(global:whereis_name(single_name)),

    ?UNTIL(begin
	       {Ns2, []} = rpc:multicall(Nodes, erlang, whereis,
					 [single_name]),
 	       6 =:= lists:foldl(fun(undefined, N) -> N + 1;
                                    (_, N) -> N
                                 end,
                                 0, Ns2)
	   end),

    assert_pid(global:send(single_name, die)),

    ?UNTIL(OrigNames =:= global:registered_names()),

    write_high_level_trace(Config),
    stop_node(Cp0),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(Cp4),
    stop_node(Cp5),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% Test ticket: Global should keep track of all pids that set the same lock.
otp_1849(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    {ok, Cp1} = start_node(cp1, Config),
    {ok, Cp2} = start_node(cp2, Config),
    {ok, Cp3} = start_node(cp3, Config),

    wait_for_ready_net(Config),

    %% start procs on each node
    Pid1 = rpc:call(Cp1, ?MODULE, start_proc, []),
    assert_pid(Pid1),
    Pid2 = rpc:call(Cp2, ?MODULE, start_proc, []),
    assert_pid(Pid2),
    Pid3 = rpc:call(Cp3, ?MODULE, start_proc, []),
    assert_pid(Pid3),

    %% set a lock on every node
    true = req(Pid1, {set_lock2, {test_lock, ?MODULE}, self()}),
    true = req(Pid2, {set_lock2, {test_lock, ?MODULE}, self()}),
    true = req(Pid3, {set_lock2, {test_lock, ?MODULE}, self()}),

    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock1}] = 
                   rpc:call(Cp1, ets, tab2list, [global_locks]),
               3 =:= length(Lock1)
           end),

    true = req(Pid3, {del_lock2, {test_lock, ?MODULE}, self()}),
    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock2}] = 
                   rpc:call(Cp1, ets, tab2list, [global_locks]),
               2 =:= length(Lock2)
           end),

    true = req(Pid2, {del_lock2, {test_lock, ?MODULE}, self()}),
    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock3}] = 
                   rpc:call(Cp1, ets, tab2list, [global_locks]),
               1 =:= length(Lock3)
           end),

    true = req(Pid1, {del_lock2, {test_lock, ?MODULE}, self()}),
    ?UNTIL([] =:= rpc:call(Cp1, ets, tab2list, [global_locks])),


    true = req(Pid1, {set_lock2, {test_lock, ?MODULE}, self()}),
    true = req(Pid2, {set_lock2, {test_lock, ?MODULE}, self()}),
    true = req(Pid3, {set_lock2, {test_lock, ?MODULE}, self()}),
    false = req(Pid2, {set_lock2, {test_lock, not_valid}, self()}),

    exit_p(Pid1),
    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock10}] = 
                   rpc:call(Cp1, ets, tab2list, [global_locks]),
               2 =:= length(Lock10)
           end),
    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock11}] = 
                   rpc:call(Cp2, ets, tab2list, [global_locks]),
               2 =:= length(Lock11)
           end),
    ?UNTIL(begin
               [{test_lock, ?MODULE, Lock12}] = 
                   rpc:call(Cp3, ets, tab2list, [global_locks]),
               2 =:= length(Lock12)
           end),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    init_condition(Config),
    ok.


%% Test ticket: Deadlock in global.
otp_3162(Config) when is_list(Config) ->
    StartFun = fun() ->
                       {ok, Cp1} = start_node(cp1, peer, Config),
                       {ok, Cp2} = start_node(cp2, peer, Config),
                       {ok, Cp3} = start_node(cp3, peer, Config),
                       [Cp1, Cp2, Cp3]
               end,
    do_otp_3162(StartFun, Config).

do_otp_3162(StartFun, Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    [Cp1, Cp2, Cp3] = StartFun(),

    wait_for_ready_net(Config),

    ThisNode = node(),

    PartCntrlr = setup_partitions(Config, [[ThisNode, Cp1, Cp2, Cp3]]),

    %% start procs on each node
    Pid1 = rpc:call(Cp1, ?MODULE, start_proc4, [kalle]),
    assert_pid(Pid1),
    Pid2 = rpc:call(Cp2, ?MODULE, start_proc4, [stina]),
    assert_pid(Pid2),
    Pid3 = rpc:call(Cp3, ?MODULE, start_proc4, [vera]),
    assert_pid(Pid3),

    disconnect_nodes(PartCntrlr, Cp1, Cp2),
    %% Nowadays we do not know how the net have been partitioned after the
    %% disconnect, so we cannot perform all the tests this testcase originally
    %% did. We instead only test the end result is ok after we have reconnected
    %% all nodes.

    erpc:call(PartCntrlr,
              fun () ->
                      erpc:cast(Cp1, net_kernel, connect_node, [Cp3]),
                      erpc:cast(Cp2, net_kernel, connect_node, [Cp3]),
                      erpc:cast(ThisNode, net_kernel, connect_node, [Cp3])
              end),

    ?UNTIL(lists:sort([ThisNode, Cp1, Cp2]) =:=
               lists:sort(erpc:call(Cp3, erlang, nodes, []))),
    ?UNTIL([kalle, stina, vera] =:=
	       lists:sort(erpc:call(Cp3, global, registered_names, []))),

    write_high_level_trace(Config),
    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_partition_controller(PartCntrlr),
    init_condition(Config),
    ok.


%% OTP-5640. 'allow' multiple names for registered processes.
otp_5640(Config) when is_list(Config) ->
    Timeout = 25,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    {ok, B} = start_node(b, Config),

    Nodes = lists:sort([node(), B]),
    wait_for_ready_net(Nodes, Config),

    Server = whereis(global_name_server),
    ServerB = rpc:call(B, erlang, whereis, [global_name_server]),

    Me = self(),
    Proc = spawn(fun() -> otp_5640_proc(Me) end),

    yes = global:register_name(name1, Proc),
    no = global:register_name(name2, Proc),

    ok = application:set_env(kernel, global_multi_name_action, allow),
    yes = global:register_name(name2, Proc),

    ct:sleep(100),
    Proc = global:whereis_name(name1),
    Proc = global:whereis_name(name2),
    check_everywhere(Nodes, name1, Config),
    check_everywhere(Nodes, name2, Config),

    {monitors_2levels, MonBy1} = mon_by_servers(Proc),
    [] = ([Server,Server,ServerB,ServerB] -- MonBy1),
    {links,[]} = process_info(Proc, links),
    _ = global:unregister_name(name1),

    ct:sleep(100),
    undefined = global:whereis_name(name1),
    Proc = global:whereis_name(name2),
    check_everywhere(Nodes, name1, Config),
    check_everywhere(Nodes, name2, Config),

    {monitors_2levels, MonBy2} = mon_by_servers(Proc),
    [] = ([Server,ServerB] -- MonBy2),
    TmpMonBy2 = MonBy2 -- [Server,ServerB],
    TmpMonBy2 = TmpMonBy2 -- [Server,ServerB],
    {links,[]} = process_info(Proc, links),

    yes = global:register_name(name1, Proc),

    Proc ! die,

    ct:sleep(100),
    undefined = global:whereis_name(name1),
    undefined = global:whereis_name(name2),
    check_everywhere(Nodes, name1, Config),
    check_everywhere(Nodes, name2, Config),
    {monitors, GMonitors} = process_info(Server, monitors),
    false = lists:member({process, Proc}, GMonitors),

    write_high_level_trace(Config),
    stop_node(B),
    init_condition(Config),
    ok.

otp_5640_proc(_Parent) ->
    receive 
        die ->
            exit(normal)
    end.

%% OTP-5737. set_lock/3 and trans/4 accept Retries = 0.
otp_5737(Config) when is_list(Config) ->
    Timeout = 25,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),

    LockId = {?MODULE,self()},
    Nodes = [node()],
    {'EXIT', _} = (catch global:set_lock(LockId, Nodes, -1)),
    {'EXIT', _} = (catch global:set_lock(LockId, Nodes, a)),
    true = global:set_lock(LockId, Nodes, 0),
    Time1 = erlang:timestamp(),
    false = global:set_lock({?MODULE,not_me}, Nodes, 0),
    true = timer:now_diff(erlang:timestamp(), Time1) < 5000,
    _ = global:del_lock(LockId, Nodes),

    Fun = fun() -> ok end,
    {'EXIT', _} = (catch global:trans(LockId, Fun, Nodes, -1)),
    {'EXIT', _} = (catch global:trans(LockId, Fun, Nodes, a)),
    ok = global:trans(LockId, Fun, Nodes, 0),

    write_high_level_trace(Config),
    init_condition(Config),
    ok.

connect_all_false(Config) when is_list(Config) ->
    %% OTP-6931. Ignore nodeup when connect_all=false.
    connect_all_false_test("-connect_all false", Config),
    %% OTP-17934: multipl -connect_all false and kernel parameter connect_all
    connect_all_false_test("-connect_all false -connect_all false", Config),
    connect_all_false_test("-kernel connect_all false", Config),
    ok.

connect_all_false_test(CAArg, Config) ->
    Me = self(),
    {ok, CAf} = start_non_connecting_node(ca_false, Config),
    {ok, false} = rpc:call(CAf, application, get_env, [kernel, connect_all]),
    ok = rpc:call(CAf, error_logger, add_report_handler, [?MODULE, Me]),
    info = rpc:call(CAf, error_logger, warning_map, []),
    {global_name_server,CAf} ! {nodeup, fake_node, #{connection_id => 4711}},
    timer:sleep(100),
    stop_node(CAf),
    receive {nodeup,fake_node, _} ->
            ct:fail({info_report, was, sent})
    after 1000 -> ok
    end,
    ok.

%%%-----------------------------------------------------------------
%%% Testing a disconnected node. Not two partitions.
%%%-----------------------------------------------------------------
%% OTP-5563. Disconnected nodes (not partitions).
simple_disconnect(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    %% Three nodes (test_server, n_1, n_2). 
    [Cp1, Cp2] = Cps = start_nodes([n_1, n_2], peer, Config),
    wait_for_ready_net(Config),

    PartCtrlr = start_partition_controller(Config),

    Nodes = lists:sort([node() | Cps]),

    lists:foreach(fun(N) -> rpc:call(N, ?MODULE, start_tracer, []) end,Nodes),

    Name = name,
    Resolver = {no_module, resolve_none}, % will never be called
    PingNode = Cp2,

    {_Pid1, yes} =
        rpc:call(Cp1, ?MODULE, start_resolver, [Name, Resolver]),
    ct:sleep(100),

    %% Disconnect test_server and Cp2. 
    disconnect_nodes(PartCtrlr, node(), Cp2),
    %% We might have been disconnected from Cp1 as well. Ensure connected
    %% to Cp1...
    pong = net_adm:ping(Cp1),

    %% _Pid is registered on Cp1. The exchange of names between Cp2 and
    %% test_server sees two identical pids.
    pong = net_adm:ping(PingNode),

    ?UNTIL(Cps =:= lists:sort(nodes())),

    {_, Trace0} = collect_tracers(Nodes),
    Resolvers = [P || {_Node,new_resolver,{pid,P}} <- Trace0],
    check_everywhere(Nodes, Name, Config),
    true = undefined /= global:whereis_name(Name),
    lists:foreach(fun(P) -> P ! die end, Resolvers),
    lists:foreach(fun(P) -> wait_for_exit(P) end, Resolvers),
    check_everywhere(Nodes, Name, Config),
    undefined = global:whereis_name(Name),

    {_, Trace1} = collect_tracers(Nodes),
    Trace = Trace0 ++ Trace1, 
    [] = [foo || {_, resolve_none, _, _} <- Trace],

    Gs = name_servers(Nodes),
    [_, _, _] = monitored_by_node(Trace, Gs),

    lists:foreach(fun(N) -> rpc:call(N, ?MODULE, stop_tracer, []) end, Nodes),

    OrigNames = global:registered_names(),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%%%-----------------------------------------------------------------
%%% Testing resolve of name. Many combinations with four nodes.
%%%-----------------------------------------------------------------
-record(cf, {
          link,  % node expected to have registered process running
          ping,  % node in partition 2 to be pinged
          n1,    % node starting registered process in partition 1
          n2,    % node starting registered process in partition 2
          nodes, % nodes expected to exist after ping
          n_res, % expected number of resolvers after ping
          config,
          ctrlr
         }).

-define(RES(F), {F, fun ?MODULE:F/3}).

%% OTP-5563. Partitions and names.
simple_resolve(Config) when is_list(Config) ->
    Timeout = 360,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [N1, A2, Z2] = Cps = start_nodes([n_1, a_2, z_2], peer, Config),
    Nodes = lists:sort([node() | Cps]),
    wait_for_ready_net(Config),

    PartCtrlr = start_partition_controller(Config),

    lists:foreach(fun(N) -> 
                          rpc:call(N, ?MODULE, start_tracer, [])
                  end, Nodes),

    %% There used to be a link between global_name_server and the
    %% registered name. Now there are only monitors, but the field
    %% name 'link' remains...

    Cf = #cf{link = none, ping = A2, n1 = node(), n2 = A2,
             nodes = [node(), N1, A2, Z2], n_res = 2, config = Config,
             ctrlr = PartCtrlr},

    %% There is no test with a resolver that deletes a pid (like
    %% global_exit_name does). The resulting DOWN signal just clears
    %% out the pid from the tables, which should be harmless. So all
    %% tests are done with resolvers that keep both processes. This
    %% should catch all cases which used to result in bogus process
    %% links (now: only monitors are used).

    %% Two partitions are created in each case below: [node(), n_1]
    %% and [a_2, z_2]. A name ('name') is registered in both
    %% partitions whereafter node() or n_1 pings a_2 or z_2. Note that
    %% node() = test_server, which means that node() < z_2 and node()
    %% > a_2. The lesser node calls the resolver.

    %% [The following comment does not apply now that monitors are used.]
    %% The resolver is run on a_2 with the process on node()
    %% as first argument. The process registered as 'name' on a_2 is
    %% removed from the tables. It is unlinked from a_2, and the new
    %% process (on node()) is inserted without trying to link to it
    %% (it it known to run on some other node, in the other
    %% partition). The new process is not sent to the other partition
    %% for update since it already exists there.
    res(?RES(resolve_first), Cps, Cf#cf{link = node(), n2 = A2}),
    %% The same, but the z_2 takes the place of a_2.
    res(?RES(resolve_first), Cps, Cf#cf{link = node(), n2 = Z2}),
    %% The resolver is run on test_server. 
    res(?RES(resolve_first), Cps, Cf#cf{link = A2, n2 = A2, ping = Z2}),
    res(?RES(resolve_first), Cps, Cf#cf{link = Z2, n2 = Z2, ping = Z2}),
    %% Now the same tests but with n_1 taking the place of test_server.
    res(?RES(resolve_first), Cps, Cf#cf{link = N1, n1 = N1, n2 = A2}),
    res(?RES(resolve_first), Cps, Cf#cf{link = N1, n1 = N1, n2 = Z2}),
    res(?RES(resolve_first), Cps, Cf#cf{link = A2, n1 = N1, n2 = A2, ping = Z2}),
    res(?RES(resolve_first), Cps, Cf#cf{link = Z2, n1 = N1, n2 = Z2, ping = Z2}),

    %% [Maybe this set of tests is the same as (ismorphic to?) the last one.]
    %% The resolver is run on a_2 with the process on node()
    %% as first argument. The process registered as 'name' on a_2 is
    %% the one kept. The old process is unlinked on node(), and the
    %% new process (on a_2) is inserted without trying to link to it
    %% (it it known to run on some other node).
    res(?RES(resolve_second), Cps, Cf#cf{link = A2, n2 = A2}),
    %% The same, but the z_2 takes the place of a_2.
    res(?RES(resolve_second), Cps, Cf#cf{link = Z2, n2 = Z2}),
    %% The resolver is run on test_server. 
    res(?RES(resolve_second), Cps, Cf#cf{link = node(), n2 = A2, ping = Z2}),
    res(?RES(resolve_second), Cps, Cf#cf{link = node(), n2 = Z2, ping = Z2}),
    %% Now the same tests but with n_1 taking the place of test_server.
    res(?RES(resolve_second), Cps, Cf#cf{link = A2, n1 = N1, n2 = A2}),
    res(?RES(resolve_second), Cps, Cf#cf{link = Z2, n1 = N1, n2 = Z2}),
    res(?RES(resolve_second), Cps, Cf#cf{link = N1, n1 = N1, n2 = A2, ping = Z2}),
    res(?RES(resolve_second), Cps, Cf#cf{link = N1, n1 = N1, n2 = Z2, ping = Z2}),

    %% A resolver that does not return one of the pids.
    res(?RES(bad_resolver), Cps, Cf#cf{n2 = A2}),
    res(?RES(bad_resolver), Cps, Cf#cf{n2 = Z2}),
    %% The resolver is run on test_server. 
    res(?RES(bad_resolver), Cps, Cf#cf{n2 = A2, ping = Z2}),
    res(?RES(bad_resolver), Cps, Cf#cf{n2 = Z2, ping = Z2}),
    %% Now the same tests but with n_1 taking the place of test_server.
    res(?RES(bad_resolver), Cps, Cf#cf{n1 = N1, n2 = A2}),
    res(?RES(bad_resolver), Cps, Cf#cf{n1 = N1, n2 = Z2}),
    res(?RES(bad_resolver), Cps, Cf#cf{n1 = N1, n2 = A2, ping = Z2}),
    res(?RES(bad_resolver), Cps, Cf#cf{n1 = N1, n2 = Z2, ping = Z2}),

    %% Both processes are unlinked (demonitored).
    res(?RES(resolve_none), Cps, Cf#cf{n2 = A2}),
    res(?RES(resolve_none), Cps, Cf#cf{n2 = Z2}),
    res(?RES(resolve_none), Cps, Cf#cf{n2 = A2, ping = Z2}),
    res(?RES(resolve_none), Cps, Cf#cf{n2 = Z2, ping = Z2}),
    res(?RES(resolve_none), Cps, Cf#cf{n1 = N1, n2 = A2}),
    res(?RES(resolve_none), Cps, Cf#cf{n1 = N1, n2 = Z2}),
    res(?RES(resolve_none), Cps, Cf#cf{n1 = N1, n2 = A2, ping = Z2}),
    res(?RES(resolve_none), Cps, Cf#cf{n1 = N1, n2 = Z2, ping = Z2}),

    %% A resolver faking badrpc. The resolver is run on a_2, and the
    %% process on node() is kept.
    res(?RES(badrpc_resolver), Cps, Cf#cf{link = node(), n2 = A2}),

    %% An exiting resolver. A kind of badrpc.
    res(?RES(exit_resolver), Cps, Cf#cf{link = node(), n2 = A2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = node(), n2 = Z2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = A2, n2 = A2, ping = Z2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = Z2, n2 = Z2, ping = Z2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = N1, n1 = N1, n2 = A2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = N1, n1 = N1, n2 = Z2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = A2, n1 = N1, n2 = A2, ping = Z2}),
    res(?RES(exit_resolver), Cps, Cf#cf{link = Z2, n1 = N1, n2 = Z2, ping = Z2}),

    %% A locker that takes a lock. It used to be that the
    %% global_name_server was busy exchanging names, which caused a
    %% deadlock.
    res(?RES(lock_resolver), Cps, Cf#cf{link = node()}),

    %% A resolver that disconnects from the node of the first pid
    %% once. The nodedown message is processed (the resolver killed),
    %% then a new attempt (nodeup etc.) is made. This time the
    %% resolver does not disconnect any node.
    res(?RES(disconnect_first), Cps, Cf#cf{link = Z2, n2 = Z2,
					   nodes = [node(), N1, A2, Z2]}),

    lists:foreach(fun(N) ->
			  rpc:call(N, ?MODULE, stop_tracer, [])
		  end, Nodes),

    OrigNames = global:registered_names(),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% OTP-5563. Partitions and names.
simple_resolve2(Config) when is_list(Config) ->
    %% Continuation of simple_resolve. Of some reason it did not
    %% always work to re-start z_2. "Cannot be a global bug."

    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [N1, A2, Z2] = Cps = start_nodes([n_1, a_2, z_2], peer, Config),
    wait_for_ready_net(Config),
    Nodes = lists:sort([node() | Cps]),

    PartCtrlr = start_partition_controller(Config),

    lists:foreach(fun(N) -> 
                          rpc:call(N, ?MODULE, start_tracer, [])
                  end, Nodes),

    Cf = #cf{link = none, ping = A2, n1 = node(), n2 = A2,
             nodes = [node(), N1, A2, Z2], n_res = 2, config = Config,
             ctrlr = PartCtrlr},

    %% Halt z_2. 
    res(?RES(halt_second), Cps, Cf#cf{link = N1, n1 = N1, n2 = Z2, ping  = A2,
				      nodes = [node(), N1, A2], n_res = 1}),

    lists:foreach(fun(N) ->
			  rpc:call(N, ?MODULE, stop_tracer, [])
		  end, Nodes),

    OrigNames = global:registered_names(),
    write_high_level_trace(Config),
    stop_nodes(Cps), % Not all nodes may be present, but it works anyway.
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% OTP-5563. Partitions and names.
simple_resolve3(Config) when is_list(Config) ->
    %% Continuation of simple_resolve.

    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [N1, A2, Z2] = Cps = start_nodes([n_1, a_2, z_2], peer, Config),
    wait_for_ready_net(Config),
    Nodes = lists:sort([node() | Cps]),

    PartCtrlr = start_partition_controller(Config),

    lists:foreach(fun(N) -> 
                          rpc:call(N, ?MODULE, start_tracer, [])
                  end, Nodes),

    Cf = #cf{link = none, ping = A2, n1 = node(), n2 = A2,
             nodes = [node(), N1, A2, Z2], n_res = 2, config = Config,
             ctrlr = PartCtrlr},

    %% Halt a_2. 
    res(?RES(halt_second), Cps, Cf#cf{link = node(), n2 = A2, 
                                      nodes = [node(), N1], n_res = 1}),

    lists:foreach(fun(N) ->
			  rpc:call(N, ?MODULE, stop_tracer, [])
		  end, Nodes),

    OrigNames = global:registered_names(),
    write_high_level_trace(Config),
    stop_nodes(Cps), % Not all nodes may be present, but it works anyway.
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

res({Res,Resolver}, [N1, A2, Z2], Cf) ->
    %% Note: there are no links anymore, but monitors.
    #cf{link = LinkedNode, ping = PingNode, n1 = Res1, n2 = OtherNode,
        nodes = Nodes0, n_res = NRes, config = Config, ctrlr = PartCtrlr} = Cf,
    io:format("~n~nResolver: ~p", [Res]),
    io:format(" Registered on partition 1:  ~p", [Res1]),
    io:format(" Registered on partition 2:  ~p", [OtherNode]),
    io:format(" Pinged node:                ~p", [PingNode]),
    io:format(" Linked node:                ~p", [LinkedNode]),
    io:format(" Expected # resolvers:       ~p", [NRes]),
    Nodes = lists:sort(Nodes0),
    T1 = node(),
    Part1 = [T1, N1],
    Part2 = [A2, Z2],
    Name = name,

    %% A registered name is resolved in different scenarios with just
    %% four nodes. In each scenario it is checked that exactly the
    %% expected monitors remain between registered processes and the
    %% global_name_server.

    setup_partitions(PartCtrlr, [Part1, Part2]),

    erpc:call(PartCtrlr,
              fun () ->
                      erpc:call(OtherNode,
                                fun () ->
                                        {Pid2, yes} = start_resolver(Name,
                                                                     Resolver),
                                        trace_message({node(), part_2_2,
                                                       nodes(), {pid2,Pid2}})
                                end)
              end),

    {_Pid1, yes} =
        rpc:call(Res1, ?MODULE, start_resolver, [Name, Resolver]),

    pong = net_adm:ping(PingNode),
    wait_for_ready_net(Nodes, Config),

    check_everywhere(Nodes, Name, Config),
    case global:whereis_name(Name) of
	undefined when LinkedNode =:= none -> ok;
	Pid -> assert_pid(Pid)
    end,

    {_, Trace0} = collect_tracers(Nodes),
    Resolvers = [P || {_Node,new_resolver,{pid,P}} <- Trace0],

    NRes = length(Resolvers),

    %% Wait for extra monitor processes to be created.
    %% This applies as long as global:do_monitor/1 spawns processes.
    %% (Some day monitor() will be truly synchronous.)
    ct:sleep(100),

    lists:foreach(fun(P) -> P ! die end, Resolvers),
    lists:foreach(fun(P) -> wait_for_exit(P) end, Resolvers),

    check_everywhere(Nodes, Name, Config),
    undefined = global:whereis_name(Name),

    %% Wait for monitors to remove names.
    ct:sleep(100),

    {_, Trace1} = collect_tracers(Nodes),
    Trace = Trace0 ++ Trace1, 

    Gs = name_servers([T1, N1, A2, Z2]),
    MonitoredByNode = monitored_by_node(Trace, Gs),
    MonitoredBy = [M || {_N,M} <- MonitoredByNode],

    X = MonitoredBy -- Gs,
    LengthGs = length(Gs),
    case MonitoredBy of
	[] when LinkedNode =:= none -> ok;
	Gs -> ok;
	_ when LengthGs < 4, X =:= [] -> ok;
	_ -> io:format("ERROR:~nMonitoredBy ~p~n"
		       "global_name_servers ~p~n",
		       [MonitoredByNode, Gs]),
	     ct:fail(monitor_mismatch)
    end,
    ok.

name_servers(Nodes) ->
    lists:sort([rpc:call(N, erlang, whereis, [global_name_server]) || 
                   N <- Nodes,
                   pong =:= net_adm:ping(N)]).

monitored_by_node(Trace, Servers) ->
    lists:sort([{node(M),M} || 
                   {_Node,_P,died,{monitors_2levels,ML}} <- Trace, 
                   M <- ML,
                   lists:member(M, Servers)]).

resolve_first(name, Pid1, _Pid2) ->
    Pid1.

resolve_second(name, _Pid1, Pid2) ->
    Pid2.

resolve_none(name, _Pid1, _Pid2) ->
    none.

bad_resolver(name, _Pid1, _Pid2) ->
    bad_answer.

badrpc_resolver(name, _Pid1, _Pid2) ->
    {badrpc, badrpc}.

exit_resolver(name, _Pid1, _Pid2) ->
    erlang:error(bad_resolver).

lock_resolver(name, Pid1, _Pid2) ->
    Id = {?MODULE, self()},
    Nodes = [node()],
    true = global:set_lock(Id, Nodes),
    _ = global:del_lock(Id, Nodes),
    Pid1.

disconnect_first(name, Pid1, Pid2) ->
    Name = disconnect_first_name,
    case whereis(Name) of
        undefined -> 
            spawn(fun() -> disconnect_first_name(Name) end),
            true = erlang:disconnect_node(node(Pid1));
        Pid when is_pid(Pid) ->
            Pid ! die
    end,
    Pid2.

disconnect_first_name(Name) ->
    register(Name, self()),
    receive die -> ok end.

halt_second(name, _Pid1, Pid2) ->
    rpc:call(node(Pid2), erlang, halt, []),
    Pid2.

start_resolver(Name, Resolver) ->
    Self = self(), 
    Pid = spawn(fun() -> init_resolver(Self, Name, Resolver) end),
    trace_message({node(), new_resolver, {pid, Pid}}),
    receive
	{Pid, Res} -> {Pid, Res}
    end.

init_resolver(Parent, Name, Resolver) ->
    X = global:register_name(Name, self(), Resolver),
    Parent ! {self(), X},
    loop_resolver().

loop_resolver() ->
    receive
        die ->
            trace_message({node(), self(), died, mon_by_servers(self())}),
            exit(normal)
    end.

%% The server sometimes uses an extra process for monitoring. 
%% The server monitors that extra process.
mon_by_servers(Proc) ->
    {monitored_by, ML} = process_info(Proc, monitored_by),
    {monitors_2levels, 
     lists:append([ML | 
                   [begin
                        {monitored_by, MML} = rpc:call(node(M), 
                                                       erlang, 
                                                       process_info, 
                                                       [M, monitored_by]),
                        MML
                    end || M <- ML]])}.

-define(REGNAME, contact_a_2).

%% OTP-5563. Bug: nodedown while syncing.
leftover_name(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),
    [N1, A2, Z2] = Cps = start_nodes([n_1, a_2, z_2], peer,  Config),
    Nodes = lists:sort([node() | Cps]),
    wait_for_ready_net(Config),

    lists:foreach(fun(N) -> 
                          rpc:call(N, ?MODULE, start_tracer, [])
                  end, Nodes),

    Name = name, % registered on a_2
    ResName = resolved_name, % registered on n_1 and a_2
    %% 
    _Pid = ping_a_2_fun(?REGNAME, N1, A2),

    T1 = node(),
    Part1 = [T1, N1],
    Part2 = [A2, Z2],
    NoResolver = {no_module, resolve_none},
    Resolver = fun contact_a_2/3,

    PartCtrlr = setup_partitions(Config, [Part1, Part2]),

    erpc:call(
      PartCtrlr,
      fun () ->
              erpc:call(
                A2,
                fun () ->
                        lists:foreach(
                          fun({TheName, TheResolver}) ->
                                  {Pid2, yes} = start_resolver(TheName, TheResolver),
                                  trace_message({node(), part_2_2, nodes(), {pid2,Pid2}})
                          end, [{Name, NoResolver}, {ResName, Resolver}])
                end)
      end),

    %% resolved_name is resolved to run on a_2, an insert operation is
    %% sent to n_1. The resolver function halts a_2, but the nodedown
    %% message is handled by n_1 _before_ the insert operation is run
    %% (at least every now and then; sometimes it seems to be
    %% delayed). Unless "artificial" nodedown messages are sent the
    %% name would linger on indefinitely. [There is no test case for
    %% the situation that no nodedown message at all is sent.]
    {_Pid1, yes} =
        rpc:call(N1, ?MODULE, start_resolver, 
                 [ResName, fun contact_a_2/3]),
    ct:sleep(1000),

    trace_message({node(), pinging, z_2}),
    pong = net_adm:ping(Z2),
    ?UNTIL((Nodes -- [A2]) =:= lists:sort(?NODES)),
    ct:sleep(1000),

    {_,Trace0} = collect_tracers(Nodes),

    Resolvers = [P || {_Node,new_resolver,{pid,P}} <- Trace0],
    lists:foreach(fun(P) -> P ! die end, Resolvers),
    lists:foreach(fun(P) -> wait_for_exit(P) end, Resolvers),

    lists:foreach(fun(N) ->
			  rpc:call(N, ?MODULE, stop_tracer, [])
		  end, Nodes),

    ?UNTIL(OrigNames =:= global:registered_names()),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

%% Runs on n_1
contact_a_2(resolved_name, Pid1, Pid2) ->
    trace_message({node(), ?REGNAME, {pid1,Pid1}, {pid2,Pid2}, 
		   {node1,node(Pid1)}, {node2,node(Pid2)}}),
    ?REGNAME ! doit,
    Pid2.

ping_a_2_fun(RegName, N1, A2) ->
    spawn(N1, fun() -> ping_a_2(RegName, N1, A2) end).

ping_a_2(RegName, N1, A2) ->
    register(RegName, self()),
    receive doit -> 
            trace_message({node(), ping_a_2, {a2, A2}}),
            monitor_node(A2, true),
            %% Establish contact with a_2, then take it down.
            rpc:call(N1, ?MODULE, halt_node, [A2]),
            receive
                {nodedown, A2} -> ok
            end
    end.

halt_node(Node) ->
    rpc:call(Node, erlang, halt, []).

%%%-----------------------------------------------------------------
%%% Testing re-registration of a name.
%%%-----------------------------------------------------------------
%% OTP-5563. Name is re-registered.
re_register_name(Config) when is_list(Config) ->
    %% When re-registering a name the link to the old pid used to
    %% linger on. Don't think is was a serious bug though--some memory
    %% occupied by links, that's all.
    %% Later: now monitors are checked.
    Timeout = 15,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    Me = self(),
    Pid1 = spawn(fun() -> proc(Me) end),
    yes = global:register_name(name, Pid1),
    wait_for_monitor(Pid1),
    Pid2 = spawn(fun() -> proc(Me) end),
    _ = global:re_register_name(name, Pid2),
    wait_for_monitor(Pid2),
    Pid2 ! die,
    Pid1 ! die,
    receive {Pid1, MonitoredBy1} -> [] = MonitoredBy1 end,
    receive {Pid2, MonitoredBy2} -> [_] = MonitoredBy2 end,
    _ = global:unregister_name(name),
    init_condition(Config),
    ok.

wait_for_monitor(Pid) ->
    case process_info(Pid, monitored_by) of
        {monitored_by, []} ->
            timer:sleep(1),
            wait_for_monitor(Pid);
        {monitored_by, [_]} ->
            ok
    end.

proc(Parent) ->
    receive die -> ok end,
    {monitored_by, MonitoredBy} = process_info(self(), monitored_by),
    Parent ! {self(), MonitoredBy}.


%%%-----------------------------------------------------------------
%%% 
%%%-----------------------------------------------------------------
%% OTP-5563. Registered process dies.
name_exit(Config) when is_list(Config) ->
    StartFun = fun() ->
                       {ok, N1} = start_node_rel(n_1, this, Config),
                       {ok, N2} = start_node_rel(n_2, this, Config),
                       [N1, N2]
               end,
    io:format("Test of current release~n"),
    do_name_exit(StartFun, current, Config).

do_name_exit(StartFun, Version, Config) ->
    %% When a registered process dies, the node where it is registered
    %% removes the name from the table immediately, and then removes
    %% it from other nodes using a lock.
    %% This is perhaps not how it should work, but it is not easy to
    %% change.
    %% See also OTP-3737.
    %%
    %% The current release uses monitors so this test is not so relevant.

    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    %% Three nodes (test_server, n_1, n_2). 
    Cps = StartFun(),
    Nodes = lists:sort([node() | Cps]),
    wait_for_ready_net(Config),
    lists:foreach(fun(N) -> rpc:call(N, ?MODULE, start_tracer, []) end,Nodes),

    Name = name,
    {Pid, yes} = start_proc(Name),

    Me = self(),
    LL = spawn(fun() -> long_lock(Me) end),
    receive 
        long_lock_taken -> ok
    end,

    Pid ! die,                    
    wait_for_exit_fast(Pid),

    ct:sleep(100),
    %% Name has been removed from node()'s table, but nowhere else
    %% since there is a lock on 'global'.
    {R1,[]} = rpc:multicall(Nodes, global, whereis_name, [Name]),
    case Version of
	old -> [_,_] = lists:usort(R1);
	current -> [undefined, undefined, undefined] = R1
    end,
    ct:sleep(3000),
    check_everywhere(Nodes, Name, Config),

    lists:foreach(fun(N) -> rpc:call(N, ?MODULE, stop_tracer, []) end, Nodes),
    OrigNames = global:registered_names(),
    exit(LL, kill),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    init_condition(Config),
    ok.

long_lock(Parent) ->
    global:trans({?GLOBAL_LOCK,self()}, 
                 fun() -> 
                         Parent ! long_lock_taken,
                         timer:sleep(3000) 
                 end).

%%%-----------------------------------------------------------------
%%% Testing the support for external nodes (cnodes)
%%%-----------------------------------------------------------------
%% OTP-5563. External nodes (cnodes).
external_nodes(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    [NodeB, NodeC] = start_nodes([b, c], peer, Config),
    wait_for_ready_net(Config),

    %% Nodes = ?NODES,
    %% lists:foreach(fun(N) -> rpc:call(N, ?MODULE, start_tracer, []) end,
    %%               Nodes),
    Name = name,

    %% Two partitions: [test_server] and [b, c].
    %% c registers an external name on b

    PartCtrlr = setup_partitions(Config, [[node()], [NodeB, NodeC]]),

    erpc:call(
      PartCtrlr,
      fun () ->
              erpc:call(
                NodeB,
                fun () ->
                        Pid = spawn(NodeC, fun() -> cnode_proc(NodeB) end),
                        Pid ! {register, self(), Name},
                        receive {Pid, Reply} -> yes = Reply end,
                        erpc:call(NodeC, erlang, register, [Name, Pid])
                end)
      end),

    pong = net_adm:ping(NodeB),
    ?UNTIL([NodeB, NodeC] =:= lists:sort(nodes())),
    wait_for_ready_net(Config),

    Cpid = rpc:call(NodeC, erlang, whereis, [Name]),
    ExternalName = [{name,Cpid,NodeB}],
    ExternalName = get_ext_names(),
    ExternalName = rpc:call(NodeB, gen_server, call,
			    [global_name_server, get_names_ext]),
    ExternalName = rpc:call(NodeC, gen_server, call,
			    [global_name_server, get_names_ext]),

    [_] = cnode_links(Cpid),
    [_,_,_] = cnode_monitored_by(Cpid),
    no = global:register_name(Name, self()),
    yes = global:re_register_name(Name, self()),
    ?UNTIL([] =:= cnode_monitored_by(Cpid)),
    ?UNTIL([] =:= cnode_links(Cpid)),
    [] = gen_server:call(global_name_server, get_names_ext, infinity),

    Cpid ! {register, self(), Name},
    receive {Cpid, Reply1} -> no = Reply1 end,
    _ = global:unregister_name(Name),
    ct:sleep(1000),
    Cpid ! {register, self(), Name},
    ?UNTIL(length(get_ext_names()) =:= 1),
    receive {Cpid, Reply2} -> yes = Reply2 end,

    Cpid ! {unregister, self(), Name},
    ?UNTIL(length(get_ext_names()) =:= 0),
    receive {Cpid, Reply3} -> ok = Reply3 end,

    Cpid ! die,
    ?UNTIL(OrigNames =:= global:registered_names()),
    [] = get_ext_names(),
    [] = rpc:call(NodeB, gen_server, call,
		  [global_name_server, get_names_ext]),
    [] = rpc:call(NodeC, gen_server, call,
		  [global_name_server, get_names_ext]),

    Cpid2 = erlang:spawn(NodeC, fun() -> cnode_proc(NodeB) end),
    Cpid2 ! {register, self(), Name},
    receive {Cpid2, Reply4} -> yes = Reply4 end,

    %% It could be a bug that Cpid2 is linked to 'global_name_server'
    %% at node 'b'. The effect: Cpid2 dies when node 'b' crashes.
    stop_node(NodeB),
    ?UNTIL(OrigNames =:= global:registered_names()),
    [] = get_ext_names(),
    [] = rpc:call(NodeC, gen_server, call,
		  [global_name_server, get_names_ext]),

    %% {_, Trace} = collect_tracers(Nodes),
    %% lists:foreach(fun(M) -> erlang:display(M) end, Trace),

    ThisNode = node(),
    Cpid3 = erlang:spawn(NodeC, fun() -> cnode_proc(ThisNode) end),
    Cpid3 ! {register, self(), Name},
    receive {Cpid3, Reply5} -> yes = Reply5 end,

    ?UNTIL(length(get_ext_names()) =:= 1),
    stop_node(NodeC),
    stop_partition_controller(PartCtrlr),
    ?UNTIL(length(get_ext_names()) =:= 0),

    init_condition(Config),
    ok.

get_ext_names() ->
    gen_server:call(global_name_server, get_names_ext, infinity).

cnode_links(Pid) ->
    Pid ! {links, self()},
    receive 
        {links, Links} ->
            Links
    end.

cnode_monitored_by(Pid) ->
    Pid ! {monitored_by, self()},
    receive 
        {monitored_by, MonitoredBy} ->
            MonitoredBy
    end.

cnode_proc(E) ->
    receive
        {register, From, Name} ->
            Rep = rpc:call(E, global, register_name_external, [Name, self()]),
            From ! {self(), Rep};
        {unregister, From, Name} ->
            _ = rpc:call(E, global, unregister_name_external, [Name]),
            From ! {self(), ok};
        {links, From} ->
            From ! process_info(self(), links);
        {monitored_by, From} ->
            From ! process_info(self(), monitored_by);
        die ->
            exit(normal)
    end,
    cnode_proc(E).


%% OTP-5770. Start many nodes. Make them connect at the same time.
many_nodes(Config) when is_list(Config) ->
    Timeout = 240,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    {Rels, N_cps} = 
        case os:type() of
            {unix, Osname} when Osname =:= linux; 
                                Osname =:= openbsd; 
                                Osname =:= darwin ->
                N_nodes = quite_a_few_nodes(32),
                {node_rel(1, N_nodes), N_nodes};
            {unix, _} ->
                {node_rel(1, 32), 32};
            _ -> 
                {node_rel(1, 32), 32}
        end,
    Cps = [begin {ok, Cp} = start_node_rel(Name, Rel, Config), Cp end ||
	      {Name,Rel} <- Rels],
    Nodes = lists:sort(?NODES),
    wait_for_ready_net(Nodes, Config),

    %% All nodes isolated not connected to any other (visible) nodes...
    Partitions = [[node()] | lists:map(fun (Node) -> [Node] end, Cps)],

    PartCtrlr = setup_partitions(Config, Partitions),

    Time = msec(),

    erpc:call(
      PartCtrlr,
      fun () ->
              OkRes = lists:map(fun (_) -> {ok, ok} end, Cps),
              OkRes = erpc:multicall(
                        Cps,
                        fun () ->
                                lists:foreach(fun(N) ->
                                                      _ = net_adm:ping(N)
                                              end, shuffle(Cps)),
                                ?UNTIL((Cps -- get_known(node())) =:= []),
                                ok
                        end),
              ok
      end),

    Time2 = msec(),

    lists:foreach(fun(N) -> pong = net_adm:ping(N) end, Cps),

    wait_for_ready_net(Config),

    write_high_level_trace(Config), % The test succeeded, but was it slow?

    ?UNTIL(OrigNames =:= global:registered_names()),
    write_high_level_trace(Config),
    stop_nodes(Cps),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    Diff = Time2 - Time,
    Return = lists:flatten(io_lib:format("~w nodes took ~w ms", 
                                         [N_cps, Diff])),
    erlang:display({{nodes,N_cps},{time,Diff}}),
    io:format("~s~n", [Return]),
    {comment, Return}.

node_rel(From, To) ->
    NodeNumbers = lists:seq(From, To),
    Release = erlang:system_info(otp_release),
    LastRelease = integer_to_list(list_to_integer(Release) - 1) ++ "_latest",
    Last = case test_server:is_release_available(LastRelease) of
               true -> list_to_atom(LastRelease);
               false -> this
           end,
    [{lists:concat([cp, N]),
      case N rem 2 of
          0 -> this;
          1 -> Last
      end} || N <- NodeNumbers].

touch(File, List) ->
    ok = file:write_file(File, list_to_binary(List)).

append_to_file(File, Term) ->
    {ok, Fd} = file:open(File, [raw,binary,append]),
    ok = file:write(Fd, io_lib:format("~p.~n", [Term])),
    ok = file:close(Fd).

file_contents(File, ContentsList, Config) ->
    file_contents(File, ContentsList, Config, no_log_file).

file_contents(File, ContentsList, Config, LogFile) ->
    Contents = list_to_binary(ContentsList),    
    Sz = size(Contents),
    ?UNTIL(begin
               case file:read_file(File) of
                   {ok, FileContents}=Reply -> 
                       case catch split_binary(FileContents, Sz) of
                           {Contents,_} ->
                               true;
                           _ ->
                               catch append_to_file(LogFile,
                                                    {File,Contents,Reply}),
                               false
                       end;
                   Reply ->
                       catch append_to_file(LogFile, {File, Contents, Reply}),
                       false
               end
           end).

shuffle(L) ->
    [E || {_, E} <- lists:keysort(1, [{rand:uniform(), E} || E <- L])].

%% OTP-5770. sync/0.
sync_0(Config) when is_list(Config) ->
    Timeout = 180,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),

    N_cps = 
        case os:type() of
            {unix, Osname} when Osname =:= linux; 
                                Osname =:= openbsd; 
                                Osname =:= darwin ->
                quite_a_few_nodes(30);
            {unix, sunos} ->
                30;
            {unix, _} ->
                16;
            _ -> 
                30
        end,

    Names = [lists:concat([cp,N]) || N <- lists:seq(1, N_cps)],
    Cps = start_and_sync(Names),
    wait_for_ready_net(Config),
    write_high_level_trace(Config),
    stop_nodes(Cps),

    init_condition(Config),
    ok.

start_and_sync([]) ->
    [];
start_and_sync([Name | Names]) ->
    {ok, N} = start_node(Name, slave, []),
    {Time, _Void} = rpc:call(N, timer, tc, [global, sync, []]),
    io:format("~p: ~p~n", [Name, Time]),
    [N | start_and_sync(Names)].

%%%-----------------------------------------------------------------
%%% Testing of change of global_groups parameter.
%%%-----------------------------------------------------------------
%% Test change of global_groups parameter.
global_groups_change(Config) ->
    Timeout = 90,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    M = from($@, atom_to_list(node())),

    %% Create the .app files and the boot script
    {KernelVer, StdlibVer} = create_script_dc("dc"),
    case is_real_system(KernelVer, StdlibVer) of
	true ->
	    Options = [];
	false  ->
	    Options = [local]
    end,

    ok = systools:make_script("dc", Options),

    [Ncp1,Ncp2,Ncp3,Ncp4,Ncp5,NcpA,NcpB,NcpC,NcpD,NcpE] = 
        node_names([cp1,cp2,cp3,cp4,cp5,cpA,cpB,cpC,cpD,cpE], Config),

    %% Write config files
    Dir = proplists:get_value(priv_dir,Config),
    {ok, Fd_dc} = file:open(filename:join(Dir, "sys.config"), [write]),
    config_dc1(Fd_dc, Ncp1, Ncp2, Ncp3, NcpA, NcpB, NcpC, NcpD, NcpE),
    file:close(Fd_dc),
    Config1 = filename:join(Dir, "sys"),

    %% Test [cp1, cp2, cp3]
    {ok, Cp1} = start_node_boot(Ncp1, Config1, dc),
    {ok, Cp2} = start_node_boot(Ncp2, Config1, dc),
    {ok, Cp3} = start_node_boot(Ncp3, Config1, dc),
    {ok, CpA} = start_node_boot(NcpA, Config1, dc),
    {ok, CpB} = start_node_boot(NcpB, Config1, dc),
    {ok, CpC} = start_node_boot(NcpC, Config1, dc),
    {ok, CpD} = start_node_boot(NcpD, Config1, dc),
    {ok, CpE} = start_node_boot(NcpE, Config1, dc),

    pong = rpc:call(Cp1, net_adm, ping, [Cp2]),
    pong = rpc:call(Cp1, net_adm, ping, [Cp3]),
    pang = rpc:call(Cp1, net_adm, ping,
		    [list_to_atom(lists:concat(["cp5@", M]))]),
    pong = rpc:call(Cp2, net_adm, ping, [Cp3]),
    pang = rpc:call(Cp2, net_adm, ping,
		    [list_to_atom(lists:concat(["cp5@", M]))]),

    {TestGG4, yes} = rpc:call(CpB, ?MODULE, start_proc, [test]),
    {TestGG5, yes} = rpc:call(CpE, ?MODULE, start_proc, [test]),


    pong = rpc:call(CpA, net_adm, ping, [CpC]),
    pong = rpc:call(CpC, net_adm, ping, [CpB]),
    pong = rpc:call(CpD, net_adm, ping, [CpC]),
    pong = rpc:call(CpE, net_adm, ping, [CpD]),

    ?UNTIL(begin
               TestGG4_1 = rpc:call(CpA, global, whereis_name, [test]),
               TestGG4_2 = rpc:call(CpB, global, whereis_name, [test]),
               TestGG4_3 = rpc:call(CpC, global, whereis_name, [test]),

               TestGG5_1 = rpc:call(CpD, global, whereis_name, [test]),
               TestGG5_2 = rpc:call(CpE, global, whereis_name, [test]),
               io:format("~p~n", [[TestGG4, TestGG4_1, TestGG4_2,TestGG4_3]]),
               io:format("~p~n", [[TestGG5, TestGG5_1, TestGG5_2]]),
               (TestGG4_1 =:= TestGG4) and
               (TestGG4_2 =:= TestGG4) and
               (TestGG4_3 =:= TestGG4) and
               (TestGG5_1 =:= TestGG5) and
               (TestGG5_2 =:= TestGG5)
           end),

    io:format( "#### nodes() ~p~n",[nodes()]),

    XDcWa1 = rpc:call(Cp1, global_group, info, []),
    XDcWa2 = rpc:call(Cp2, global_group, info, []),
    XDcWa3 = rpc:call(Cp3, global_group, info, []),
    io:format( "#### XDcWa1 ~p~n",[XDcWa1]),
    io:format( "#### XDcWa2 ~p~n",[XDcWa2]),
    io:format( "#### XDcWa3 ~p~n",[XDcWa3]),

    stop_node(CpC),

    %% Read the current configuration parameters, and change them
    OldEnv =
        rpc:call(Cp1, application_controller, prep_config_change, []),
    {value, {kernel, OldKernel}} = lists:keysearch(kernel, 1, OldEnv),

    GG1 =
        lists:sort([mk_node(Ncp1, M), mk_node(Ncp2, M), mk_node(Ncp5, M)]),
    GG2 = lists:sort([mk_node(Ncp3, M)]),
    GG3 = lists:sort([mk_node(Ncp4, M)]),
    GG4 = lists:sort([mk_node(NcpA, M), mk_node(NcpB, M)]),
    GG5 =
        lists:sort([mk_node(NcpC, M), mk_node(NcpD, M), mk_node(NcpE, M)]),

    NewNG = {global_groups,[{gg1, normal, GG1},
			    {gg2, normal, GG2},
			    {gg3, normal, GG3},
			    {gg4, normal, GG4},
			    {gg5, hidden, GG5}]},

    NewKernel =
        [{kernel, lists:keyreplace(global_groups, 1, OldKernel, NewNG)}],
    ok = rpc:call(Cp1, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(Cp2, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(Cp3, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(CpA, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(CpB, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(CpD, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),
    ok = rpc:call(CpE, application_controller, test_change_apps,
		  [[kernel], [NewKernel]]),

    io:format("####  ~p~n",[multicall]),
    io:format( "####  ~p~n",[multicall]),
    %% no idea to check the result from the rpc because the other
    %% nodes will disconnect test server, and thus the result will
    %% always be {badrpc, nodedown}
    rpc:multicall([Cp1, Cp2, Cp3, CpA, CpB, CpD, CpE],
		  application_controller, config_change, [OldEnv]),

    {ok, Fd_dc2} = file:open(filename:join(Dir, "sys2.config"), [write]),
    config_dc2(Fd_dc2, NewNG, Ncp1, Ncp2, Ncp3),
    file:close(Fd_dc2),
    Config2 = filename:join(Dir, "sys2"),
    {ok, CpC} = start_node_boot(NcpC, Config2, dc),

    gg_sync_and_wait(Cp1, [Cp2], [], [mk_node(Ncp5, M)]),
    gg_sync_and_wait(CpA, [CpB], [], []),
    gg_sync_and_wait(CpD, [CpC, CpE], [], []),

    pong = rpc:call(CpA, net_adm, ping, [CpC]),
    pong = rpc:call(CpC, net_adm, ping, [CpB]),
    pong = rpc:call(CpD, net_adm, ping, [CpC]),
    pong = rpc:call(CpE, net_adm, ping, [CpD]),

    GG5 =
        lists:sort([mk_node(NcpC, M)|rpc:call(CpC, erlang, nodes, [])]),
    GG5 =
        lists:sort([mk_node(NcpD, M)|rpc:call(CpD, erlang, nodes, [])]),
    GG5 =
        lists:sort([mk_node(NcpE, M)|rpc:call(CpE, erlang, nodes, [])]),

    false =
        lists:member(mk_node(NcpC, M), rpc:call(CpA, erlang, nodes, [])),
    false =
        lists:member(mk_node(NcpC, M), rpc:call(CpB, erlang, nodes, [])),

    ?UNTIL(begin
               TestGG4a = rpc:call(CpA, global, whereis_name, [test]),
               TestGG4b = rpc:call(CpB, global, whereis_name, [test]),

               TestGG5c = rpc:call(CpC, global, whereis_name, [test]),
               TestGG5d = rpc:call(CpD, global, whereis_name, [test]),
               TestGG5e = rpc:call(CpE, global, whereis_name, [test]),
               io:format("~p~n", [[TestGG4, TestGG4a, TestGG4b]]),
               io:format("~p~n", [[TestGG5, TestGG5c, TestGG5d, TestGG5e]]),
               (TestGG4 =:= TestGG4a) and
               (TestGG4 =:= TestGG4b) and
               (TestGG5 =:= TestGG5c) and
               (TestGG5 =:= TestGG5d) and
               (TestGG5 =:= TestGG5e)
           end),

    Info1 = rpc:call(Cp1, global_group, info, []),
    Info2 = rpc:call(Cp2, global_group, info, []),
    Info3 = rpc:call(Cp3, global_group, info, []),
    InfoA = rpc:call(CpA, global_group, info, []),
    InfoB = rpc:call(CpB, global_group, info, []),
    InfoC = rpc:call(CpC, global_group, info, []),
    InfoD = rpc:call(CpD, global_group, info, []),
    InfoE = rpc:call(CpE, global_group, info, []),
    io:format( "#### Info1 ~p~n",[Info1]),
    io:format( "#### Info2 ~p~n",[Info2]),
    io:format( "#### Info3 ~p~n",[Info3]),
    io:format( "#### InfoA ~p~n",[InfoA]),
    io:format( "#### InfoB ~p~n",[InfoB]),
    io:format( "#### InfoC ~p~n",[InfoC]),
    io:format( "#### InfoD ~p~n",[InfoD]),
    io:format( "#### InfoE ~p~n",[InfoE]),

    {global_groups, GGNodes} = NewNG,

    Info1ok = [{state, synced},
	       {own_group_name, gg1},
	       {own_group_nodes, GG1},
	       {synced_nodes, [mk_node(Ncp2, M)]},
	       {sync_error, []},
	       {no_contact, [mk_node(Ncp5, M)]},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg1, 1, GGNodes))},
	       {monitoring, []}],


    Info2ok = [{state, synced},
	       {own_group_name, gg1},
	       {own_group_nodes, GG1},
	       {synced_nodes, [mk_node(Ncp1, M)]},
	       {sync_error, []},
	       {no_contact, [mk_node(Ncp5, M)]},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg1, 1, GGNodes))},
	       {monitoring, []}],

    Info3ok = [{state, synced},
	       {own_group_name, gg2},
	       {own_group_nodes, GG2},
	       {synced_nodes, []},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg2, 1, GGNodes))},
	       {monitoring, []}],

    InfoAok = [{state, synced},
	       {own_group_name, gg4},
	       {own_group_nodes, GG4},
	       {synced_nodes, lists:delete(mk_node(NcpA, M), GG4)},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg4, 1, GGNodes))},
	       {monitoring, []}],

    InfoBok = [{state, synced},
	       {own_group_name, gg4},
	       {own_group_nodes, GG4},
	       {synced_nodes, lists:delete(mk_node(NcpB, M), GG4)},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg4, 1, GGNodes))},
	       {monitoring, []}],

    InfoCok = [{state, synced},
	       {own_group_name, gg5},
	       {own_group_nodes, GG5},
	       {synced_nodes, lists:delete(mk_node(NcpC, M), GG5)},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg5, 1, GGNodes))},
	       {monitoring, []}],

    InfoDok = [{state, synced},
	       {own_group_name, gg5},
	       {own_group_nodes, GG5},
	       {synced_nodes, lists:delete(mk_node(NcpD, M), GG5)},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg5, 1, GGNodes))},
	       {monitoring, []}],

    InfoEok = [{state, synced},
	       {own_group_name, gg5},
	       {own_group_nodes, GG5},
	       {synced_nodes, lists:delete(mk_node(NcpE, M), GG5)},
	       {sync_error, []},
	       {no_contact, []},
	       {other_groups, remove_gg_pub_type(lists:keydelete
						   (gg5, 1, GGNodes))},
	       {monitoring, []}],


    case Info1 of
	Info1ok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [Info1ok, Info1]),
	    ct:fail({{"could not change the global groups"
		      " in node", Cp1}, {Info1, Info1ok}})
    end,

    case Info2 of
	Info2ok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [Info2ok, Info2]),
	    ct:fail({{"could not change the global groups"
		      " in node", Cp2}, {Info2, Info2ok}})
    end,

    case Info3 of
	Info3ok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [Info3ok, Info3]),
	    ct:fail({{"could not change the global groups"
		      " in node", Cp3}, {Info3, Info3ok}})
    end,

    case InfoA of
	InfoAok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [InfoAok, InfoA]),
	    ct:fail({{"could not change the global groups"
		      " in node", CpA}, {InfoA, InfoAok}})
    end,

    case InfoB of
	InfoBok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [InfoBok, InfoB]),
	    ct:fail({{"could not change the global groups"
		      " in node", CpB}, {InfoB, InfoBok}})
    end,


    case InfoC of
	InfoCok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [InfoCok, InfoC]),
	    ct:fail({{"could not change the global groups"
		      " in node", CpC}, {InfoC, InfoCok}})
    end,

    case InfoD of
	InfoDok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [InfoDok, InfoD]),
	    ct:fail({{"could not change the global groups"
		      " in node", CpD}, {InfoD, InfoDok}})
    end,

    case InfoE of
	InfoEok ->
	    ok;
	_ ->
            ct:pal("Expected: ~p~n"
                   "Got     : ~p~n",
                   [InfoEok, InfoE]),
	    ct:fail({{"could not change the global groups"
		      " in node", CpE}, {InfoE, InfoEok}})
    end,

    write_high_level_trace(Config), % no good since CpC was restarted
    stop_node(Cp1),   
    stop_node(Cp2),   
    stop_node(Cp3),  
    stop_node(CpA),
    stop_node(CpB),
    stop_node(CpC),
    stop_node(CpD),
    stop_node(CpE),

    init_condition(Config),
    ok.

gg_sync_and_wait(Node, Synced, SyncError, NoContact) ->
    ok = rpc:call(Node, global_group, sync, []),
    gg_wait(Node, Synced, SyncError, NoContact).

gg_wait(Node, Synced, SyncError, NoContact) ->
    receive after 100 -> ok end,
    try
        GGInfo = rpc:call(Node, global_group, info, []),
        ct:pal("GG info: ~p~n", [GGInfo]),
        case proplists:lookup(synced_nodes, GGInfo) of
            {synced_nodes, Synced} -> ok;
            _ -> throw(wait)
        end,
        case proplists:lookup(sync_error, GGInfo) of
            {sync_error, SyncError} -> ok;
            _ -> throw(wait)
        end,
        case proplists:lookup(no_contact, GGInfo) of
            {no_contact, NoContact} -> ok;
            _ -> throw(wait)
        end
    catch
        throw:wait ->
            gg_wait(Node, Synced, SyncError, NoContact)
    end.

%%% Copied from init_SUITE.erl.
is_real_system(KernelVsn, StdlibVsn) ->
    LibDir = code:lib_dir(),
    filelib:is_dir(filename:join(LibDir,  "kernel-" ++ KernelVsn))
	andalso
	filelib:is_dir(filename:join(LibDir,  "stdlib-" ++ StdlibVsn)).

create_script_dc(ScriptName) ->
    Name = filename:join(".", ScriptName),
    Apps = application_controller:which_applications(),
    {value,{_,_,KernelVer}} = lists:keysearch(kernel,1,Apps),
    {value,{_,_,StdlibVer}} = lists:keysearch(stdlib,1,Apps),
    {ok,Fd} = file:open(Name ++ ".rel", [write]),
    {_, Version} = init:script_id(),
    io:format(Fd,
	      "{release, {\"Test release 3\", \"~s\"}, \n"
	      " {erts, \"4.4\"}, \n"
	      " [{kernel, \"~s\"}, {stdlib, \"~s\"}]}.\n",
	      [Version, KernelVer, StdlibVer]),
    file:close(Fd),
    {KernelVer, StdlibVer}.

%% Not used?
config_dc(Fd, Ncp1, Ncp2, Ncp3) ->
    M = from($@, atom_to_list(node())),
    io:format(Fd, "[{kernel, [{sync_nodes_optional, ['~s@~s','~s@~s','~s@~s']},"
	      "{sync_nodes_timeout, 1000},"
	      "{global_groups, [{gg1, ['~s@~s', '~s@~s']},"
	      "               {gg2, ['~s@~s']}]}"
	      "              ]}].~n",
	      [Ncp1, M, Ncp2, M, Ncp3, M,  Ncp1, M, Ncp2, M, Ncp3, M]).


config_dc1(Fd, Ncp1, Ncp2, Ncp3, NcpA, NcpB, NcpC, NcpD, NcpE) ->
    M = from($@, atom_to_list(node())),
    io:format(Fd, "[{kernel, [{sync_nodes_optional, ['~s@~s','~s@~s','~s@~s','~s@~s','~s@~s','~s@~s','~s@~s','~s@~s']},"
	      "{sync_nodes_timeout, 1000},"
	      "{global_groups, [{gg1, ['~s@~s', '~s@~s']},"
	      "                 {gg2, ['~s@~s']},"
	      "                 {gg4, normal, ['~s@~s','~s@~s','~s@~s']},"
	      "                 {gg5, hidden, ['~s@~s','~s@~s']}]}]}].~n",
	      [Ncp1, M, Ncp2, M, Ncp3, M,  
               NcpA, M, NcpB, M, NcpC, M, NcpD, M, NcpE, M, 
               Ncp1, M, Ncp2, M, 
               Ncp3, M, 
               NcpA, M, NcpB, M, NcpC, M, 
               NcpD, M, NcpE, M]).

config_dc2(Fd, NewGG, Ncp1, Ncp2, Ncp3) ->
    M = from($@, atom_to_list(node())),
    io:format(Fd, "[{kernel, [{sync_nodes_optional, ['~s@~s','~s@~s','~s@~s']},"
	      "{sync_nodes_timeout, 1000},"
	      "~p]}].~n",
	      [Ncp1, M, Ncp2, M, Ncp3, M, NewGG]).


from(H, [H | T]) -> T;
from(H, [_ | T]) -> from(H, T);
from(_H, []) -> [].



other(A, [A, _B]) -> A;
other(_, [_A, B]) -> B.

w(X,Y) ->
    {ok, F} = file:open("cp2.log", [write]),
    io:format(F, X, Y),
    file:close(F).

start_procs(Parent, N1, N2, N3, Config) ->
    S1 = lists:sort([N1, N2, N3]),
    ?UNTIL(begin
	       NN = lists:sort(nodes()),
	       S1 =:= NN
	   end),
    Pid3 = start_proc3(test1),
    Pid4 = rpc:call(N1, ?MODULE, start_proc3, [test2]),
    assert_pid(Pid4),
    Pid5 = rpc:call(N2, ?MODULE, start_proc3, [test3]),
    assert_pid(Pid5),
    Pid6 = rpc:call(N3, ?MODULE, start_proc3, [test4]),
    assert_pid(Pid6),
    yes = global:register_name(test1, Pid3),
    yes = global:register_name(test2, Pid4, fun global:notify_all_name/3),
    yes = global:register_name(test3, Pid5, fun global:random_notify_name/3),
    Resolve = fun(Name, Pid1, Pid2) ->
		      Parent ! {resolve_called, Name, node()},
		      {Min, Max} = minmax(Pid1, Pid2),
		      exit(Min, kill),
		      Max
	      end,
    yes = global:register_name(test4, Pid6, Resolve).



collect_resolves() -> cr(0).
cr(Res) ->
    receive
	{resolve_called, Name, Node} ->
	    ?P("resolve called: ~w ~w", [Name, Node]),
 	    cr(Res+1)
    after
	0 -> Res
    end.

minmax(P1,P2) ->
    if node(P1) < node(P2) -> {P1, P2}; true -> {P2, P1} end.

fix_basic_name(name03, Pid1, Pid2) ->
    case atom_to_list(node(Pid1)) of
	[$c, $p, $3|_] -> exit(Pid2, kill), Pid1;
	_ -> exit(Pid1, kill), Pid2
    end;
fix_basic_name(name12, Pid1, Pid2) ->
    case atom_to_list(node(Pid1)) of
	[$c, $p, $2|_] -> exit(Pid2, kill), Pid1;
	_ -> exit(Pid1, kill), Pid2
    end.

start_proc() ->
    Pid = spawn(?MODULE, p_init, [self()]),
    receive
	Pid -> Pid
    end.


start_proc(Name) ->
    Pid = spawn(?MODULE, p_init, [self(), Name]),
    receive
	{Pid, Res} -> {Pid, Res}
    end.

start_proc2(Name) ->
    Pid = spawn(?MODULE, p_init2, [self(), Name]),
    receive
	Pid -> Pid
    end.

start_proc3(Name) ->
    Pid = spawn(?MODULE, p_init, [self()]),
    register(Name, Pid),
    receive
	Pid -> Pid
    end.

start_proc4(Name) ->
    Pid = spawn(?MODULE, p_init, [self()]),
    yes = global:register_name(Name, Pid),
    receive
	Pid -> Pid
    end.

start_proc_basic(Name) ->
    Pid = spawn(?MODULE, init_proc_basic, [self(), Name]),
    receive
	{Pid, Res} -> {Pid, Res}
    end.

init_proc_basic(Parent, Name) ->
    X = global:register_name(Name, self(), fun ?MODULE:fix_basic_name/3),
    Parent ! {self(),X},
    loop().

single_node(Time, Node) ->
    spawn(?MODULE, init_2, []),
    timer:sleep(Time - msec()),
    _ = net_adm:ping(Node),
    ok.

init_2() ->
    register(single_name, self()),
    yes = global:register_name(single_name, self()),
    loop_2().

loop_2() ->
    receive
	die -> ok
    end.

msec() ->
    msec(erlang:timestamp()).

msec(T) ->
    element(1,T)*1000000000 + element(2,T)*1000 + element(3,T) div 1000.

assert_pid(Pid) ->
    if
	is_pid(Pid) -> true;
	true -> exit({not_a_pid, Pid})
    end.

check_same([H|T]) -> check_same(T, H).

check_same([H|T], H) -> check_same(T, H);
check_same([], _H) -> ok.

check_same_p([H|T]) -> check_same_p(T, H).

check_same_p([H|T], H) -> check_same_p(T, H);
check_same_p([], _H) -> true;
check_same_p(_, _) -> false.

p_init(Parent) ->
    Parent ! self(),
    loop().

p_init(Parent, Name) ->
    X = global:register_name(Name, self()),
    Parent ! {self(),X},
    loop().

p_init2(Parent, Name) ->
    _ = global:re_register_name(Name, self()),
    Parent ! self(),
    loop().

req(Pid, Msg) ->
    Pid ! Msg,
    receive X -> X end.

sreq(Pid, Msg) ->
    Ref = make_ref(),
    Pid ! {Msg, Ref},
    receive {Ref, X} -> X end.

alone(N1, N2) ->
    ct:sleep(12000),
    net_adm:ping(N1),
    net_adm:ping(N2),
    yes = global:register_name(test5, self()).

crash(Time) ->
    %% ct:sleep/1 will not work because it calls a server process
    %% that does not run on other nodes.
    timer:sleep(Time),
    erlang:halt().

loop() ->
    receive
	{ping, From} ->
	    From ! {pong, node()},
	    loop();
	{del_lock, Id} ->
	    global:del_lock({Id, self()}),
	    loop();
	{del_lock_sync, Id, From} ->
	    global:del_lock({Id, self()}),
	    From ! true,
	    loop();
	{del_lock, Id, Nodes} ->
	    global:del_lock({Id, self()}, Nodes),
	    loop();
	{del_lock2, Id, From} ->
	    global:del_lock(Id),
	    From ! true,
	    loop();
	{del_lock2, Id, From, Nodes} ->
	    global:del_lock(Id, Nodes),
	    From ! true,
	    loop();
	{set_lock, Id, From} ->
	    Res = global:set_lock({Id, self()}, ?NODES, 1),
	    From ! Res,
	    loop();
	{set_lock, Id, From, Nodes} ->
	    Res = global:set_lock({Id, self()}, Nodes, 1),
	    From ! Res,
	    loop();
	{set_lock_loop, Id, From} ->
	    true = global:set_lock({Id, self()}, ?NODES),
	    From ! {got_lock, self()},
	    loop();
	{set_lock2, Id, From} ->
	    Res = global:set_lock(Id, ?NODES, 1),
	    From ! Res,
	    loop();
	{{got_notify, From}, Ref} ->
	    receive
		X when element(1, X) =:= global_name_conflict ->
		    From ! {Ref, yes}
	    after
		0 -> From ! {Ref, no}
	    end,
	    loop();
	die ->
	    exit(normal);
	drop_dead ->
	    exit(drop_dead)
    end.

-ifdef(unused).
pr_diff(Str, T0, T1) ->
    Diff = begin
	       {_, {H,M,S}} = calendar:time_difference(T0, T1),
	       ((H*60+M)*60)+S
	   end,
    ct:pal(?HI_VERBOSITY,"~13s: ~w (diff: ~w)",[Str, T1, Diff]),
    if
	Diff > 100 ->
	    io:format(1,"~s: ** LARGE DIFF ~w~n", [Str, Diff]);
	true -> 
	    ok
    end.
-endif.	    

now_diff({A1,B1,C1},{A2,B2,C2}) ->
    C1-C2 + 1000000*((B1-B2) + 1000000*(A1-A2)).

start_node_boot(Name, Config, Boot) ->
    Pa = filename:dirname(code:which(?MODULE)),
    Res = test_server:start_node(Name, peer, [{args, " -pa " ++ Pa ++ 
						   " -config " ++ Config ++
						   " -boot " ++ atom_to_list(Boot)}]),
    record_started_node(Res).

%% Increase the timeout for when an upcoming connection is teared down
%% again (default is 7 seconds, and can be exceeded by some tests).
%% The default remains in effect for the test_server node itself, though.
start_node(Name, Config) ->
    start_node(Name, slave, Config).

start_hidden_node(Name, Config) ->
    start_node(Name, slave, "-hidden", Config).

start_non_connecting_node(Name, Config) ->
    start_node(Name, slave, "-connect_all false +W i", Config).

start_peer_node(Name, Config) ->
    start_node(Name, peer, Config).

start_node(Name, How, Config) ->
    start_node(Name, How, "", Config).

start_node(Name0, How, Args, Config) ->
    Name = node_name(Name0, Config),
    Pa = filename:dirname(code:which(?MODULE)),
    R = test_server:start_node(
          Name, How, [{args,
                       Args ++
                           " -kernel net_setuptime 100 " ++
                           %% Limit the amount of threads so that we
                           %% don't run into the maximum allowed
                           " +S 1 +SDio 1 " ++
                           %% "-noshell "
                           "-pa " ++ Pa},
                      {linked, false}
                     ]),
    %% {linked,false} only seems to work for slave nodes.
    %%    ct:sleep(1000),
    record_started_node(R).

start_node_rel(Name0, Rel, Config) ->
    Name = node_name(Name0, Config),
    {Release, Compat} = case Rel of
                            this ->
                                {[this], ""};
                            Rel when is_atom(Rel) ->
                                {[{release, atom_to_list(Rel)}], ""};
                            RelList ->
				{RelList, ""}
			end,
    Env = [],
    Pa = filename:dirname(code:which(?MODULE)),
    Res = test_server:start_node(
            Name, peer,
            [{args,
              Compat ++
                  " -kernel net_setuptime 100 " ++
                  %% Limit the amount of threads so that we
                  %% don't run into the maximum allowed
                  " +S 1 +SDio 1 " ++
                  "-pa " ++ Pa},
             {erl, Release}] ++ Env),
    record_started_node(Res).

record_started_node({ok, Node}) ->
    node_started(Node),
    case erase(?nodes_tag) of
        undefined -> ok;
        Nodes -> put(?nodes_tag, [Node | Nodes])
    end,
    {ok, Node};
record_started_node(R) ->
    R.

node_names(Names, Config) ->
    [node_name(Name, Config) || Name <- Names].

%% simple_resolve assumes that the node name comes first.
node_name(Name, Config) ->
    U = "_",
    {{Y,M,D}, {H,Min,S}} = calendar:now_to_local_time(erlang:timestamp()),
    Date = io_lib:format("~4w_~2..0w_~2..0w__~2..0w_~2..0w_~2..0w", 
                         [Y,M,D, H,Min,S]),
    L = lists:flatten(Date),
    lists:concat([Name,U,?testcase,U,U,L]).

stop_nodes(Nodes) ->
    lists:foreach(fun(Node) -> stop_node(Node) end, Nodes).

stop_node(Node) ->
    Res = test_server:stop_node(Node),
    node_stopped(Node),
    Res.


stop() ->
    lists:foreach(fun(Node) ->
			  test_server:stop_node(Node),
                          node_stopped(Node)
		  end, nodes()).

%% Tests that locally loaded nodes do not loose contact with other nodes.
global_lost_nodes(Config) when is_list(Config) ->
    Timeout = 60,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),

    {ok, Node1} = start_node(node1, Config),
    {ok, Node2} = start_node(node2, Config),

    wait_for_ready_net(Config),

    io:format("Nodes: ~p", [nodes()]),
    io:format("Nodes at node1: ~p",
	      [rpc:call(Node1, erlang, nodes, [])]),
    io:format("Nodes at node2: ~p",
	      [rpc:call(Node2, erlang, nodes, [])]),

    rpc_cast(Node1, ?MODULE, global_load, [node_1,Node2,node_2]),
    rpc_cast(Node2, ?MODULE, global_load, [node_2,Node1,node_1]),

    lost_nodes_waiter(Node1, Node2),

    write_high_level_trace(Config),
    stop_node(Node1),
    stop_node(Node2),
    init_condition(Config),
    ok.    

global_load(MyName, OtherNode, OtherName) ->
    yes = global:register_name(MyName, self()),
    io:format("Registered ~p",[MyName]),
    global_load1(OtherNode, OtherName, 0).

global_load1(_OtherNode, _OtherName, 2) ->
    io:format("*** ~p giving up. No use.", [node()]),
    init:stop();
global_load1(OtherNode, OtherName, Fails) ->	
    ct:sleep(1000),
    case catch global:whereis_name(OtherName) of
	Pid when is_pid(Pid) ->
	    io:format("~p says: ~p is still there.",
		      [node(),OtherName]),
	    global_load1(OtherNode, OtherName, Fails);
	Other ->
	    io:format("~p says: ~p is lost (~p) Pinging.",
		      [ node(), OtherName, Other]),
	    case net_adm:ping(OtherNode) of
		pong ->
		    io:format("Re-established contact to ~p",
			      [OtherName]);
		pang ->
		    io:format("PANIC! Other node is DEAD.", []),
		    init:stop()
	    end,
	    global_load1(OtherNode, OtherName, Fails+1)
    end.

lost_nodes_waiter(N1, N2) ->
    net_kernel:monitor_nodes(true),
    receive
	{nodedown, Node} when Node =:= N1 ; Node =:= N2 ->
	    io:format("~p went down!",[Node]),
	    ct:fail("Node went down.")
    after 10000 ->
	    ok
    end,
    ok.



%% Tests the simultaneous death of many processes with registered names.
mass_death(Config) when is_list(Config) ->
    Timeout = 90,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),
    %% Start nodes
    Cps = [cp1,cp2,cp3,cp4,cp5],
    Nodes = [begin {ok, Node} = start_node(Cp, Config), Node end ||
		Cp <- Cps],
    io:format("Nodes: ~p~n", [Nodes]),
    Ns = lists:seq(1, 40),
    %% Start processes with globally registered names on the nodes
    {Pids,[]} = rpc:multicall(Nodes, ?MODULE, init_mass_spawn, [Ns]),
    io:format("Pids: ~p~n", [Pids]),
    %% Wait...
    ct:sleep(10000),
    %% Check the globally registered names
    NewNames = global:registered_names(),
    io:format("NewNames: ~p~n", [NewNames]),
    Ndiff = lists:sort(NewNames--OrigNames),
    io:format("Ndiff: ~p~n", [Ndiff]),
    Ndiff = lists:sort(mass_names(Nodes, Ns)),
    %%
    %% Kill the root pids
    lists:foreach(fun (Pid) -> Pid ! drop_dead end, Pids),
    %% Start probing and wait for all registered names to disappear
    {YYYY,MM,DD} = date(),
    {H,M,S} = time(),
    io:format("Started probing: ~.4.0w-~.2.0w-~.2.0w ~.2.0w:~.2.0w:~.2.0w~n",
	      [YYYY,MM,DD,H,M,S]),
    wait_mass_death(Nodes, OrigNames, erlang:timestamp(), Config).

wait_mass_death(Nodes, OrigNames, Then, Config) ->
    Names = global:registered_names(),
    case Names--OrigNames of
	[] ->
	    T = now_diff(erlang:timestamp(), Then) div 1000,
	    lists:foreach(
	      fun (Node) ->
		      stop_node(Node)
	      end, Nodes),
	    init_condition(Config),
	    {comment,lists:flatten(io_lib:format("~.3f s~n", [T/1000.0]))};
	Ndiff ->
	    io:format("Ndiff: ~p~n", [Ndiff]),
	    ct:sleep(1000),
	    wait_mass_death(Nodes, OrigNames, Then, Config)
    end.

init_mass_spawn(N) ->
    Pid = mass_spawn(N),
    unlink(Pid),
    Pid.

mass_spawn([]) ->
    ok;
mass_spawn([N|T]) ->
    Parent = self(),
    Pid = 
	spawn_link(
	  fun () ->
		  Name = mass_name(node(), N),
		  yes = global:register_name(Name, self()),
		  mass_spawn(T),
		  Parent ! self(),
		  loop()
	  end),
    receive
        Pid ->
            Pid
    end.

mass_names([], _) ->
    [];
mass_names([Node|T],Ns) ->
    [mass_name(Node, N) || N <- Ns] ++ mass_names(T, Ns).

mass_name(Node, N) ->
    list_to_atom(atom_to_list(Node)++"_"++integer_to_list(N)).



start_nodes(L, How, Config) ->
    start_nodes2(L, How, 0, Config),
    Nodes = collect_nodes(0, length(L)),
    ?UNTIL([] =:= Nodes -- nodes()),
    put(?nodes_tag, Nodes),
    %% Pinging doesn't help, we have to wait too, for nodes() to become
    %% correct on the other node.
    lists:foreach(fun(E) ->
			  net_adm:ping(E)
		  end,
		  Nodes),
    verify_nodes(Nodes, Config),
    Nodes.

%% Not used?
start_nodes_serially([], _, _Config) ->
    [];
start_nodes_serially([Name | Rest], How, Config) ->
    {ok, R} = start_node(Name, How, Config),
    [R | start_nodes_serially(Rest, How, Config)].

verify_nodes(Nodes, Config) ->
    verify_nodes(Nodes, lists:sort([node() | Nodes]), Config).

verify_nodes([], _N, _Config) ->
    [];
verify_nodes([Node | Rest], N, Config) ->
    ?UNTIL(
       case rpc:call(Node, erlang, nodes, []) of
	   Nodes when is_list(Nodes) ->
	       case N =:= lists:sort([Node | Nodes]) of
		   true ->
		       true;
		   false ->
		       lists:foreach(fun(Nd) ->
					     rpc:call(Nd, net_adm, ping,
                                                      [Node])
				     end,
				     nodes()),
		       false
	       end;
	   _ ->
	       false
       end
      ),
    verify_nodes(Rest, N, Config).


start_nodes2([], _How, _, _Config) ->
    [];
start_nodes2([Name | Rest], How, N, Config) ->
    Self = self(),
    spawn(fun() ->
		  erlang:display({starting, Name}),
		  {ok, R} = start_node(Name, How, Config),
		  erlang:display({started, Name, R}),
		  Self ! {N, R},
		  %% sleeping is necessary, or with peer nodes, they will
		  %% go down again, despite {linked, false}.
		  ct:sleep(100000)
	  end),
    start_nodes2(Rest, How, N+1, Config).

collect_nodes(N, N) ->
    [];
collect_nodes(N, Max) ->
    receive
	{N, Node} ->
            [Node | collect_nodes(N+1, Max)]
    end.

exit_p(Pid) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! die,
    receive
	{'DOWN', Ref, process, Pid, _Reason} ->
	    ok
    end.

wait_for_exit(Pid) ->
    Ref = erlang:monitor(process, Pid),
    receive
	{'DOWN', Ref, process, Pid, _Reason} ->
	    ok
    end.

wait_for_exit_fast(Pid) ->
    Ref = erlang:monitor(process, Pid),
    receive
	{'DOWN', Ref, process, Pid, _Reason} ->
	    ok
    end.

check_everywhere(Nodes, Name, Config) ->
    ?UNTIL(begin
	       case rpc:multicall(Nodes, global, whereis_name, [Name]) of
		   {Ns1, []} ->
		       check_same_p(Ns1);
		   _R ->
		       false
	       end
	   end).

init_condition(Config) ->
    io:format("globally registered names: ~p~n", [global:registered_names()]),
    io:format("nodes: ~p~n", [nodes()]),
    io:format("known: ~p~n", [get_known(node()) -- [node()]]),
    io:format("Info ~p~n", [setelement(10, global:info(), trace)]),
    _ = [io:format("~s: ~p~n", [TN, ets:tab2list(T)]) ||
            {TN, T} <- [{"Global Names     (ETS)", global_names},
                        {"Global Names Ext (ETS)", global_names_ext},
                        {"Global Locks     (ETS)", global_locks},
                        {"Global Pid Names (ETS)", global_pid_names},
                        {"Global Pid Ids   (ETS)", global_pid_ids}]],
    ?UNTIL([] =:= global:registered_names()),
    ?UNTIL([] =:= nodes()),
    ?UNTIL([node()] =:= get_known(node())),
    ok.

mk_node(N, H) when is_list(N), is_list(H) ->
    list_to_atom(N ++ "@" ++ H).

remove_gg_pub_type([]) ->
    [];
remove_gg_pub_type([{GG, Nodes}|Rest]) ->
    [{GG, Nodes}|remove_gg_pub_type(Rest)];
remove_gg_pub_type([{GG, _, Nodes}|Rest]) ->
    [{GG, Nodes}|remove_gg_pub_type(Rest)].

%% Send garbage message to all processes that are linked to global.
%% Better do this in a slave node.
%% (The transition from links to monitors does not affect this case.)

garbage_messages(Config) when is_list(Config) ->
    Timeout = 25,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    [Slave] = start_nodes([garbage_messages], slave, Config),
    Fun = fun() ->
		  {links,L} = process_info(whereis(global_name_server), links),
		  lists:foreach(fun(Pid) -> Pid ! {garbage,to,you} end, L),
		  receive
		      _Any -> ok
		  end
	  end,
    Pid = spawn_link(Slave, erlang, apply, [Fun,[]]),
    ct:sleep(2000),
    Global = rpc:call(Slave, erlang, whereis, [global_name_server]),
    {registered_name,global_name_server} =
	rpc:call(Slave, erlang, process_info, [Global,registered_name]),
    true = unlink(Pid),
    write_high_level_trace(Config),
    stop_node(Slave),
    init_condition(Config),
    ok.

%% This is scenario outlined in
%% https://erlang.org/pipermail/erlang-questions/2020-October/100034.html.
%% It illustrates that the algorithm of Global is flawed.
%%
%% This has been worked around by global actively disconnecting nodes
%% to prevent overlapping partitions (OTP-17843).
flaw1(Config) ->
    case prevent_overlapping_partitions() of
        true ->
            flaw1_test(Config);
        false ->
            {skipped, "Prevent overlapping partitions disabled"}
    end.

flaw1_test(Config) ->
    Timeout = 360,
    ct:timetrap({seconds,Timeout}),
    init_high_level_trace(Timeout),
    init_condition(Config),
    OrigNames = global:registered_names(),

    PartCtrlr = start_partition_controller(Config),

    [A, B, C, D] = OtherNodes = start_nodes([a, b, c, d], peer, Config),
    Nodes = lists:sort([node() | OtherNodes]),
    wait_for_ready_net(Config),

    F1 =
        fun(S0) ->
                ct:sleep(100),
                Str = "************",
                S = Str ++ "  " ++ lists:flatten(S0) ++ "  " ++ Str,
                io:format("~s\n", [S]),
                erpc:call(
                  PartCtrlr,
                  fun () ->
                          [begin
                               RNs = erpc:call(N, global, registered_names, []),
                               W = erpc:call(N, global, whereis_name, [x]),
                               io:format("   === ~w ===\n", [N]),
                               io:format("       registered names: ~p", [RNs]),
                               io:format("       where is x:       ~p", [W])
                           end || N <- OtherNodes]
                  end)
        end,
    F1("start"),

    disconnect_nodes(PartCtrlr, A, C),
    F1("after disconnecting c from a"),

    Me = self(),
    IdleFun = fun () ->
                      Mon = erlang:monitor(process, Me),
                      receive
                          {'DOWN', Mon, process, Me, _} ->
                              exit(normal)
                      end
              end,
    Pid = spawn(IdleFun),
    yes = rpc:call(A, global, register_name, [x, Pid]),
    F1(io_lib:format("after registering x as ~p on a", [Pid])),

    disconnect_nodes(PartCtrlr, B, D),
    F1("after disconnecting d from b"),

    Pid2 = spawn(IdleFun),
    yes = rpc:call(B, global, re_register_name, [x, Pid2]),
    F1(io_lib:format("after re_register_name x as ~p on b", [Pid2])),

    pong = rpc:call(A, net_adm, ping, [C]),
    F1("finished after ping c from a"),

    pong = rpc:call(B, net_adm, ping, [D]),
    F1("finished after ping d from b"),

    timer:sleep(1000),

    check_everywhere(Nodes, x, Config),
    F1("After check everywhere"),

    assert_pid(global:whereis_name(x)),

    lists:foreach(fun(N) ->
			  rpc:call(N, ?MODULE, stop_tracer, [])
		  end, Nodes),
    _ = rpc:call(A, global, unregister_name, [x]),

    F1("after unregistering x on node a"),

    %% _ = rpc:call(B, global, unregister_name, [y]),
    %% F1("after unregistering y on node b"),

    ct:sleep(100),
    OrigNames = global:registered_names(),
    write_high_level_trace(Config),
    stop_nodes(OtherNodes),
    stop_partition_controller(PartCtrlr),
    init_condition(Config),
    ok.

global_disconnect(Config) when is_list(Config) ->
    Timeout = 30,
    ct:timetrap({seconds,Timeout}),

    [] = nodes(connected),

    {ok, H1} = start_hidden_node(h1, Config),
    {ok, H2} = start_hidden_node(h2, Config),
    {ok, Cp1} = start_node(cp1, peer, Config),
    {ok, Cp2} = start_node(cp2, peer, Config),
    {ok, Cp3} = start_node(cp3, peer, Config),

    ThisNode = node(),
    HNodes = lists:sort([H1, H2]),
    OtherGNodes = lists:sort([Cp1, Cp2, Cp3]),
    AllGNodes = lists:sort([ThisNode|OtherGNodes]),

    lists:foreach(fun (Node) -> pong = net_adm:ping(Node) end, OtherGNodes),

    wait_for_ready_net(Config),

    ok = erpc:call(
           H2,
           fun () ->
                   lists:foreach(fun (Node) ->
                                         pong = net_adm:ping(Node)
                                 end, OtherGNodes)
           end),

    lists:foreach(
      fun (Node) ->
              AllGNodes = erpc:call(
                            H1,
                            fun () ->
                                    erpc:call(
                                      Node,
                                      fun () ->
                                              lists:sort([node()|nodes()])
                                      end)
                            end),
              HNodes = erpc:call(
                         H1,
                         fun () ->
                                 erpc:call(
                                   Node,
                                   fun () ->
                                           lists:sort(nodes(hidden))
                                   end)
                         end)
      end, AllGNodes),

    OtherGNodes = lists:sort(global:disconnect()),

    GNodesAfterDisconnect = nodes(),

    HNodes = lists:sort(nodes(hidden)),

    lists:foreach(fun (Node) ->
                          false = lists:member(Node, GNodesAfterDisconnect)
                  end,
                  OtherGNodes),

    %% Wait a while giving the other nodes time to react to the disconnects
    %% before we check that everything is as expected...
    receive after 2000 -> ok end,

    lists:foreach(
      fun (Node) ->
              OtherGNodes = erpc:call(
                              H1,
                              fun () ->
                                      erpc:call(
                                        Node,
                                        fun () ->
                                                lists:sort([node()|nodes()])
                                        end)
                              end),
              HNodes = erpc:call(
                         H1,
                         fun () ->
                                 erpc:call(
                                   Node,
                                   fun () ->
                                           lists:sort(nodes(hidden))
                                   end)
                         end)
      end, OtherGNodes),

    stop_node(Cp1),
    stop_node(Cp2),
    stop_node(Cp3),
    stop_node(H1),
    stop_node(H2),

    ok.

%% ---

wait_for_ready_net(Config) ->
    {Pid, MRef} = spawn_monitor(fun() ->
                                        wait_for_ready_net(?NODES, Config)
                                end),
    wait_for_ready_net_loop(Pid, MRef).

wait_for_ready_net_loop(Pid, MRef) ->
    receive
        {'DOWN', MRef, process, Pid, Info} ->
            ?P("wait-for-ready-net process terminated: "
               "~n      ~p", [Info]),
            ok;

        {'EXIT', ParentPid, {timetrap_timeout, _Timeout, _Stack}} ->
            ?P("wait-for-ready-net -> received timetrap timeout:"
               "~n   Regarding: ~p"
               "~n   Waiter:    ~p"
               "~n      Current Location: ~p"
               "~n      Dictionary:       ~p"
               "~n      Messages:          ~p",
               [ParentPid, Pid,
                pi(Pid, current_location),
                pi(Pid, dictionary),
                pi(Pid, messages)]),
            exit(Pid, kill),
            ct:fail("Timeout waiting for ready network")

    end.

wait_for_ready_net(Nodes0, Config) ->
    Nodes = lists:sort(Nodes0),
    ?P("wait_for_ready_net ->"
       "~n   Nodes: ~p", [Nodes]),
    ?UNTIL(begin
               lists:all(fun(N) ->
                                 ?P("wait_for_ready_net -> "
                                    "get known (by global) for ~p", [N]),
                                 GNs = get_known(N),
                                 ?P("wait_for_ready_net -> verify same for ~p:"
                                    "~n   Global Known: ~p"
                                    "~n   Nodes:        ~p", [N, GNs, Nodes]),
                                 GRes = Nodes =:= GNs,
                                 ?P("wait_for_ready_net => ~p", [GRes]),
                                 GRes
                         end,
                         Nodes) and
		   lists:all(fun(N) ->
                                     ?P("wait_for_ready_net -> "
                                        "get erlang nodes for ~p", [N]),
				     case rpc:call(N, erlang, nodes, []) of
                                         RNs0 when is_list(RNs0) ->
                                             RNs = lists:sort([N | RNs0]),
                                             ?P("wait_for_ready_net -> "
                                                "verify same for ~p: "
                                                "~n   Remote nodes:  ~p"
                                                "~n   (Local) Nodes: ~p",
                                                [N, RNs, Nodes]),
                                             ERes = Nodes =:= RNs,
                                             ?P("wait_for_ready_net => ~p",
                                                [ERes]),
                                             ERes;
                                         BadRes ->
                                             ?P("failed get nodes for ~p"
                                                "~n      ~p",
                                                [N, BadRes]),
                                             false
                                     end
			     end,
                             Nodes)
           end).

get_known(Node) ->
    case catch gen_server:call({global_name_server,Node},get_known,infinity) of
        {'EXIT', _} ->
            [list, without, nodenames];
        Known when is_list(Known) -> 
            lists:sort([Node | Known])
    end.

quite_a_few_nodes(Max) ->
    N = try 
            ulimit("ulimit -u")
        catch _:_ ->
		ulimit("ulimit -p") % can fail...
        end,
    lists:min([(N - 40) div 3, Max]).

ulimit(Cmd) ->
    N0 = os:cmd(Cmd),
    N1 = lists:reverse(N0),
    N2 = lists:dropwhile(fun($\r) -> true;
			    ($\n) -> true;
			    (_) -> false
			 end, N1),
    case lists:reverse(N2) of
        "unlimited" -> 10000;
        N -> list_to_integer(N)
    end.

%% To make it less probable that some low-level problem causes
%% problems, the receiving node is ping:ed.
rpc_cast(Node, Module, Function, Args) ->
    {_,pong,Node}= {node(),net_adm:ping(Node),Node},
    rpc:cast(Node, Module, Function, Args).

global_known(Node) ->
    gen_server:call({global_name_server, Node}, get_known, infinity).

global_known() ->
    global_known(node()).

disconnect(Node) ->
    erlang:disconnect_node(Node),
    wait_until(fun () -> not lists:member(Node, global_known()) end),
    ok.

disconnect_nodes(HiddenCtrlNode, NodeA, NodeB) ->
    Nodes = [node()|nodes()],
    ok = erpc:call(HiddenCtrlNode,
                   fun () ->
                           ok = erpc:call(NodeA,
                                          fun () ->
                                                  disconnect(NodeB)
                                          end),
                           ok = erpc:call(NodeB,
                                          fun () ->
                                                  disconnect(NodeA)
                                          end),
                           %% Try to ensure 'lost_connection' messages
                           %% have been handled (see comment in
                           %% create_partitions)...
                           lists:foreach(fun (N) ->
                                                 _ = global_known(N)
                                         end, Nodes),
                           ok
                   end).

create_partitions(PartitionsList) ->
    AllNodes = lists:sort(lists:flatten(PartitionsList)),

    %% Take down all connections on all nodes...
    AllOk = lists:map(fun (_) -> {ok, ok} end, AllNodes),
    io:format("Disconnecting all nodes from eachother...", []),
    AllOk = erpc:multicall(
              AllNodes,
              fun () ->
                      lists:foreach(fun (N) ->
                                            erlang:disconnect_node(N)
                                    end, nodes()),
                      wait_until(fun () -> [] == global_known() end),
                      ok
              end, 5000),
    %% Here we know that all 'lost_connection' messages that will be
    %% sent by global name servers due to these disconnects have been
    %% sent, but we don't know that all of them have been received and
    %% handled. By communicating with all global name servers one more
    %% time it is very likely that all of them have been received and
    %% handled (however, not guaranteed). If 'lost_connection' messages
    %% are received after we begin to set up the partitions, the
    %% partitions may lose connection with some of its nodes.
    lists:foreach(fun (N) -> [] = global_known(N) end, AllNodes),

    %% Set up fully connected partitions...
    io:format("Connecting partitions...", []),
    lists:foreach(
      fun (Partition) ->
              Part = lists:sort(Partition),
              PartOk = lists:map(fun (_) -> {ok, ok} end, Part),
              PartOk = erpc:multicall(
                         Part,
                         fun () ->
                                 wait_until(
                                   fun () ->
                                           ConnNodes = Part -- [node()|nodes()],
                                           if ConnNodes == [] ->
                                                   true;
                                              true ->
                                                   lists:foreach(
                                                     fun (N) ->
                                                             net_kernel:connect_node(N)
                                                     end, ConnNodes),
                                                   false
                                           end
                                   end),
                                 ok
                                                        
                         end, 5000)
      end, PartitionsList),
    ok.
                                                     
setup_partitions(PartCtrlr, PartList) when is_atom(PartCtrlr) ->
    ok = erpc:call(PartCtrlr, fun () -> create_partitions(PartList) end),
    io:format("Partitions successfully setup:~n", []),
    lists:foreach(fun (Part) ->
                          io:format("~p~n", [Part])
                  end,
                  PartList),
    ok;
setup_partitions(Config, PartList) when is_list(Config) ->
    PartCtrlr = start_partition_controller(Config),
    setup_partitions(PartCtrlr, PartList),
    PartCtrlr.

start_partition_controller(Config) when is_list(Config) ->
    {ok, PartCtrlr} = start_hidden_node(part_ctrlr, Config),
    PartCtrlr.

stop_partition_controller(PartCtrlr) ->
    stop_node(PartCtrlr).

prevent_overlapping_partitions() ->
    case application:get_env(kernel, prevent_overlapping_partitions) of
        {ok, false} ->
            false;
        _ ->
            true
    end.

cast_line([]) ->
    ok;
cast_line([N|Ns]) when N == node() ->
    cast_line(Ns);
cast_line([N|Ns]) ->
    erpc:cast(N, fun () -> cast_line(Ns) end).
                         
wait_until(F) ->
    case catch F() of
        true ->
            ok;
        _ ->
            receive after 10 -> ok end,
            wait_until(F)
    end.


%% The emulator now ensures that the node has been removed from
%% nodes().
rpc_disconnect_node(Node, DisconnectedNode, Config) ->
    true = rpc:call(Node, erlang, disconnect_node, [DisconnectedNode]),
    ?UNTIL
      (not lists:member(DisconnectedNode, rpc:call(Node, erlang, nodes, []))).

%%%
%%% Utility
%%%

%% It is a bit awkward to collect data from different nodes. One way
%% of doing is to use a named tracer process on each node. Interesting
%% data is banged to the tracer and when the test is finished data is
%% collected on some node by sending messages to the tracers. One
%% cannot do this if the net has been set up to be less than fully
%% connected. One can also prepare other modules, such as 'global', by
%% inserting lines like
%%   trace_message({node(), {at,?LINE}, {tag, message})
%% where appropriate.

start_tracer() ->
    Pid = spawn(fun() -> tracer([]) end),
    case catch register(my_tracer, Pid) of
        {'EXIT', _} ->
            ct:fail(re_register_my_tracer);
        _ ->
            ok
    end.

tracer(L) ->
    receive 
        %% {save, Term} ->
        %%     tracer([{erlang:timestamp(),Term} | L]);
        {get, From} ->
            From ! {trace, lists:reverse(L)},
            tracer([]);
        stop ->
            exit(normal);
        Term ->
            tracer([{erlang:timestamp(),Term} | L])
    end.

stop_tracer() ->
    trace_message(stop).

get_trace() ->
    trace_message({get, self()}),
    receive {trace, L} ->
            L
    end.

collect_tracers(Nodes) ->
    Traces0 = [rpc:call(N, ?MODULE, get_trace, []) || N <- Nodes],
    Traces = [L || L <- Traces0, is_list(L)],
    try begin 
            Stamped = lists:keysort(1, lists:append(Traces)),
            NotStamped = [T || {_, T} <- Stamped],
            {Stamped, NotStamped}
        end
    catch _:_ -> {[], []}
    end.

trace_message(M) ->
    case catch my_tracer ! M of
        {'EXIT', _} ->
            ct:fail(my_tracer_not_registered);
        _ ->
            ok
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

pi(Item) ->
    pi(self(), Item).
pi(Pid, Item) ->
    {Item, Val} = process_info(Pid, Item),
    Val.
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%-----------------------------------------------------------------
%% The error_logger handler used for OTP-6931.
%%-----------------------------------------------------------------
init(Tester) ->
    {ok, Tester}.

handle_event({_, _GL, {_Pid,_String,[{nodeup,fake_node,_}=Msg]}}, Tester) ->
    Tester ! Msg,
    {ok, Tester};
handle_event(_Event, State) ->
    {ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

handle_call(_Query, State) -> {ok, {error, bad_query}, State}.

terminate(_Reason, State) ->
    State.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%
%%% Keep track of started nodes so we can kill them if test
%%% cases fail to stop them. This typically happens on test case
%%% failure with peer nodes, and if left might mess up following
%%% test-cases.
%%%
%%% This can be removed when the suite is converted to use CT_PEER.
%%% This can however at earliest be made in OTP 25.
%%%

node_started(Node) ->
    _ = global_SUITE_node_tracker ! {node_started, Node},
    ok.

node_stopped(Node) ->
    _ = global_SUITE_node_tracker ! {node_stopped, Node},
    ok.

start_node_tracker(Config) ->
    case whereis(global_SUITE_node_tracker) of
        undefined ->
            ok;
        _ ->
            try
                stop_node_tracker(Config),
                ok
            catch
                _:_ ->
                    ok
            end
    end,
    _ = spawn(fun () ->
                      _ = register(global_SUITE_node_tracker, self()),
                      node_tracker_loop(#{})
              end),
    ok.

node_tracker_loop(Nodes) ->
    receive
        {node_started, Node} ->
            node_tracker_loop(Nodes#{Node => alive});
        {node_stopped, Node} ->
            node_tracker_loop(Nodes#{Node => stopped});
        stop ->
            Fact = try 
                       test_server:timetrap_scale_factor()
                   catch _:_ -> 1
                   end,
            Tmo = 1000*Fact,
            lists:foreach(
              fun (N) ->
                      case maps:get(N, Nodes) of
                          stopped ->
                              ok;
                          alive ->
                              ct:pal("WARNING: The node ~p was not "
                                     "stopped by the test case!", [N])
                      end,
                      %% We try to kill every node, even those reported as
                      %% stopped since they might have failed at stopping...
                      case rpc:call(N, erlang, halt, [], Tmo) of
                          {badrpc,nodedown} ->
                              ok;
                          {badrpc,timeout} ->
                              ct:pal("WARNING: Failed to kill node: ~p~n"
                                     "         Disconnecting it, but it may "
                                     "still be alive!", [N]),
                              erlang:disconnect_node(N),
                              ok;
                          Unexpected ->
                              ct:pal("WARNING: Failed to kill node: ~p~n"
                                     "         Got response: ~p~n"
                                     "         Disconnecting it, but it may "
                                     "still be alive!", [N, Unexpected]),
                              erlang:disconnect_node(N),
                              ok
                      end
              end, maps:keys(Nodes))
    end.

stop_node_tracker(Config) ->
    NTRes = case whereis(global_SUITE_node_tracker) of
                undefined ->
                    {fail, missing_node_tracker};
                NT when is_port(NT) ->
                    NTMon = erlang:monitor(port, NT),
                    exit(NT, kill),
                    receive {'DOWN', NT, port, NT, _} -> ok end,
                    {fail, {port_node_tracker, NT}};
                NT when is_pid(NT) ->
                    NTMon = erlang:monitor(process, NT),
                    NT ! stop,
                    receive
                        {'DOWN', NTMon, process, NT, normal} ->
                            ok;
                        {'DOWN', NTMon, process, NT, Reason} ->
                            {fail, {node_tracker_failed, Reason}}
                    end
            end,
    case NTRes of
        ok ->
            ok;
        NTFailure ->
            case proplists:get_value(tc_status, Config) of
                ok ->
                    %% Fail test case with info about node tracker...
                    NTFailure;
                _ ->
                    %% Don't fail due to node tracker...
                    ct:pal("WARNING: Node tracker failure: ~p", [NTFailure]),
                    ok
            end
    end.
