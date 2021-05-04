%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2016. All Rights Reserved.
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
-module(timer).

-export([apply_after/4,
	 send_after/3, send_after/2,
	 exit_after/3, exit_after/2, kill_after/2, kill_after/1,
	 apply_interval/4, send_interval/3, send_interval/2,
	 cancel/1, read/1, sleep/1, tc/1, tc/2, tc/3, now_diff/2,
	 seconds/1, minutes/1, hours/1, hms/3]).

-export([start_link/0, start/0, 
	 handle_call/3,  handle_info/2,  
	 init/1,
	 code_change/3, handle_cast/2, terminate/2]).

%% internal exports for test purposes only
-export([get_status/0]).

%% types which can be used by other modules
-export_type([tref/0]).

%% Max
-define(MAX_TIMEOUT, 16#ffffffff).

%% Validation macros.
-define(valid_tref(TRef), is_reference(element(2, TRef))).
-define(valid_time(Time), is_integer(Time), Time >= 0).
-define(valid_mfa(M, F, A), is_atom(M), is_atom(F), is_list(A)).

%%
%% Time is in milliseconds.
%%
-opaque tref()    :: {integer(), reference()}.
-type time()      :: non_neg_integer().

%%
%% Interface functions
%%

%% Apply the given function of the given module with the given
%% arguments after the given time.
-spec apply_after(Time, Module, Function, Arguments) ->
                         {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      TRef :: tref(),
      Reason :: term().
apply_after(Time, M, F, A)
  when ?valid_time(Time), ?valid_mfa(M, F, A) ->
    req(apply_after, {Time, {M, F, A}});
apply_after(_Time, _M, _F, _A) ->
    {error, badarg}.

%% Send the given message to the given pid or registered name after
%% the given time.
-spec send_after(Time, Pid, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_after(Time, Pid, Message) ->
    apply_after(Time, ?MODULE, send, [Pid, Message]).

%% Send the given message to the caller after the given time.
-spec send_after(Time, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_after(Time, Message) ->
    send_after(Time, self(), Message).

%% Send an exit signal with the given reason to the given pid or
%% registered name after the given time.
-spec exit_after(Time, Pid, Reason1) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      TRef :: tref(),
      Reason1 :: term(),
      Reason2 :: term().
exit_after(Time, Pid, Reason) ->
    apply_after(Time, erlang, exit, [Pid, Reason]).

%% Send an exit signal with the given reason to the caller after the
%% given time.
-spec exit_after(Time, Reason1) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      TRef :: tref(),
      Reason1 :: term(),
      Reason2 :: term().
exit_after(Time, Reason) ->
    exit_after(Time, self(), Reason).

%% Kill the given pid or registered name after the given time.
-spec kill_after(Time, Pid) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      TRef :: tref(),
      Reason2 :: term().
kill_after(Time, Pid) ->
    exit_after(Time, Pid, kill).

%% Kill the caller after the given time.
-spec kill_after(Time) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      TRef :: tref(),
      Reason2 :: term().
kill_after(Time) ->
    exit_after(Time, self(), kill).

%% Apply the given function of the given module with the given
%% arguments repeatedly after the given time intervals.
-spec apply_interval(Time, Module, Function, Arguments) ->
                            {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      TRef :: tref(),
      Reason :: term().
apply_interval(Time, M, F, A)
  when ?valid_time(Time), ?valid_mfa(M, F, A) ->
    req(apply_interval, {Time, self(), {M, F, A}});
apply_interval(_Time, _M, _F, _A) ->
    {error, badarg}.

%% Send the given message to the given pid or registered name repeatedly
%% after the given time intervals.
-spec send_interval(Time, Pid, Message) ->
                           {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_interval(Time, Pid, Message)
  when ?valid_time(Time), is_pid(Pid) ->
    req(apply_interval, {Time, Pid, {?MODULE, send, [Pid, Message]}});
send_interval(Time, RegName, Message)
  when ?valid_time(Time), is_atom(RegName) ->
    case get_pid(RegName) of
	Pid when is_pid(Pid) ->
	    req(apply_interval, {Time, Pid, {?MODULE, send, [Pid, Message]}});
	_ ->
	    {error, badarg}
    end;
send_interval(_Time, _PidOrRegName, _Message) ->
    {error, badarg}.

%% Send the given message to the caller repeatedly after the given
%% time intervals.
-spec send_interval(Time, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_interval(Time, Message) ->
    send_interval(Time, self(), Message).

%% Get the time left before the given timer fires.
-spec read(TRef) -> 'undefined' | {'ok', Remaining} | {'error', Reason} when
      TRef :: tref(),
      Remaining :: time(),
      Reason :: term().
read(TRef) when ?valid_tref(TRef) ->
    req(read, TRef, undefined);
read(_TRef) ->
    {error, badarg}.

%% Cancel the given timer.
-spec cancel(TRef) -> {'ok', 'cancel'} | {'error', Reason} when
      TRef :: tref(),
      Reason :: term().
cancel(TRef) when ?valid_tref(TRef) ->
    req(cancel, TRef, undefined);
cancel(_TRef) ->
    {error, badarg}.

%% Suspend the calling process for the given time.
-spec sleep(Time) -> 'ok' when
      Time :: timeout().
sleep(T) when is_integer(T), T>?MAX_TIMEOUT ->
    receive
    after ?MAX_TIMEOUT ->
	sleep(T-?MAX_TIMEOUT)
    end;
sleep(T) ->
    receive
    after T -> ok
    end.

%%
%% Measure the execution time (in microseconds) for Fun().
%%
-spec tc(Fun) -> {Time, Value} when
      Fun :: function(),
      Time :: integer(),
      Value :: term().
tc(F) ->
    T1 = erlang:monotonic_time(),
    Val = F(),
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2 - T1, native, microsecond),
    {Time, Val}.

%%
%% Measure the execution time (in microseconds) for Fun(Args).
%%
-spec tc(Fun, Arguments) -> {Time, Value} when
      Fun :: function(),
      Arguments :: [term()],
      Time :: integer(),
      Value :: term().
tc(F, A) ->
    T1 = erlang:monotonic_time(),
    Val = apply(F, A),
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2 - T1, native, microsecond),
    {Time, Val}.

%%
%% Measure the execution time (in microseconds) for an MFA.
%%
-spec tc(Module, Function, Arguments) -> {Time, Value} when
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      Time :: integer(),
      Value :: term().
tc(M, F, A) ->
    T1 = erlang:monotonic_time(),
    Val = apply(M, F, A),
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2 - T1, native, microsecond),
    {Time, Val}.

%%
%% Calculate the time difference (in microseconds) of two
%% erlang:now() timestamps, T2-T1.
%%
-spec now_diff(T2, T1) -> Tdiff when
      T1 :: erlang:timestamp(),
      T2 :: erlang:timestamp(),
      Tdiff :: integer().
now_diff({A2, B2, C2}, {A1, B1, C1}) ->
    ((A2-A1)*1000000 + B2-B1)*1000000 + C2-C1.

%%
%% Convert seconds, minutes etc. to milliseconds.    
%%
-spec seconds(Seconds) -> MilliSeconds when
      Seconds :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
seconds(Seconds) ->
    1000*Seconds.
-spec minutes(Minutes) -> MilliSeconds when
      Minutes :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
minutes(Minutes) ->
    1000*60*Minutes.
-spec hours(Hours) -> MilliSeconds when
      Hours :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
hours(Hours) ->
    1000*60*60*Hours.
-spec hms(Hours, Minutes, Seconds) -> MilliSeconds when
      Hours :: non_neg_integer(),
      Minutes :: non_neg_integer(),
      Seconds :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
hms(H, M, S) ->
    hours(H) + minutes(M) + seconds(S).

%%   
%%   Start/init functions
%%

%%   Start is only included because of backward compatibility!
-spec start() -> 'ok'.
start() ->
    ensure_started().

-spec start_link() -> {'ok', pid()} | {'error', term()}.
start_link() ->
    gen_server:start_link({local, timer_server}, ?MODULE, [], []).    

-type timers() :: ets:tab().

-spec init([]) -> {'ok', timers()}.
init([]) ->
    process_flag(trap_exit, true),
    Tab = ets:new(?MODULE, [public]),
    {ok, Tab}.

-spec ensure_started() -> 'ok'.
ensure_started() ->
    case whereis(timer_server) of
	undefined -> 
	    C = {timer_server, {?MODULE, start_link, []}, permanent, 1000, 
		 worker, [?MODULE]},
	    _ = supervisor:start_child(kernel_safe_sup, C),
	    ok;
	_ -> ok
    end.

%% server calls

req(Req, Arg, SysTime) ->
    ensure_started(),
    gen_server:call(timer_server, {Req, Arg, SysTime}, infinity).

req(Req, Arg) ->
    req(Req, Arg, tstamp()).

%%
%% Time and Timeout is in milliseconds. Started is in microseconds.
%%
-spec handle_call(term(), term(), timers()) ->
        {'reply', term(), timers()} | {'noreply', timers()}.
% One-shot timer.
handle_call({apply_after, {Time, MFA}, Started}, _From, Tab) ->
    TRef = {Started, make_ref()},
    ok = timeout_timer(TRef, Time, MFA, Tab),
    {reply, {ok, TRef}, Tab};
% Interval timer.
handle_call({apply_interval, {Time, Pid, MFA}, Started}, _From, Tab) ->
    TRef = {Started, make_ref()},
    ok = interval_timer(TRef, Time, Pid, MFA, Tab),
    {reply, {ok, TRef}, Tab};
handle_call({read, TRef, _}, From, Tab) ->
    _ = spawn(
	fun () ->
	    Reply = case ets:lookup(Tab, TRef) of
		[{TRef, TPid, _}] ->
		    MRef = monitor(process, TPid),
		    TPid ! {read, {self(), MRef}},
		    receive
			{MRef, Rem} ->
			    {ok, Rem};
			{'DOWN', MRef, process, TPid, _Reason} ->
			    undefined
		    end;
		[] ->
		    undefined
	    end,
	    gen_server:reply(From, Reply)
	end
    ),
    {noreply, Tab};
% Cancel a timer.
handle_call({cancel, TRef, _}, From, Tab) -> 
    _ = spawn(
	fun () ->
	    ok = do_cancel(TRef, Tab),
	    gen_server:reply(From, {ok, cancel})
	end
    ),
    {noreply, Tab};
% Get server status, ie the number of one-shot and interval timers.
% For debugging/testing only.
handle_call(get_status, From, Tab) ->
    spawn(
	fun () ->
	    Status = do_get_status(Tab),
	    gen_server:reply(From, Status)
	end
    ),
    {noreply, Tab};
% Ignore unexpected call messages.
handle_call(_Other, _From, Tab) ->
    {noreply, Tab}.

-spec handle_info(term(), timers()) -> {'noreply', timers()}.
% A linked process terminated. Should not happen,
% as the timer processes unlink themselves before terminating.
handle_info({'EXIT', TPid, _Reason}, Tab) ->
    spawn(
	fun () ->
	    ets:match_delete(Tab, {'_', TPid, '_'})
	end
    ),
    {noreply, Tab};
% Ignore unexpected info messages.
handle_info(_Other, Tab) ->
    {noreply, Tab}.

-spec handle_cast(term(), timers()) -> {'noreply', timers()}.
% Ignore unexpected cast messagess.
handle_cast(_Other, Tab) ->
    {noreply, Tab}.

-spec terminate(term(), _State) -> 'ok'.
% Timer server terminating normally. This should not happen,
% but if it does we need to tell the timers to cancel, because
% they will not be terminated via their links in this case.
terminate(normal, Tab) ->
    ets:foldl(
	fun ({_, TPid, _}, _) ->
	    TPid ! cancel,
	    ok
	end,
	ok,
	Tab
    );
% Other termination.
terminate(_Reason, _Tab) ->
    ok.

-spec code_change(term(), State, term()) -> {'ok', State}.
code_change(_OldVsn, State, _Extra) ->
    %% According to the man for gen server no timer can be set here.
    {ok, State}.

% If the pid of the given timer can be found in the timers table,
% tell it to cancel, then wait for the timer process to go down.
% Otherwise, do nothing.
do_cancel(TRef, Tab) ->
    case ets:lookup(Tab, TRef) of
	[{TRef, TPid, _}] ->
	    TPid ! cancel,
	    MRef = monitor(process, TPid),
	    receive
		{'DOWN', MRef, process, TPid, _Reason} -> ok
	    end;
	[] ->
	    ok
    end.

% Collect the numbers of one-shot and interval timers.
do_get_status(Tab) ->
    ets:foldl(
	fun
	    ({_, _, timeout}, Acc=#{timeout := N}) ->
		Acc#{timeout => N + 1};
	    ({_, _, interval}, Acc=#{interval := N}) ->
		Acc#{interval => N + 1}
	end,
	#{timeout => 0, interval => 0},
	Tab
    ).

% Start a one-shot timer.
% Waits for the given time to elapse, then applies the given
% MFA and stops. Stops without applying the MFA when a cancel
% message is received.
timeout_timer(TRef, Time, MFA, Tab) ->
    TsPid = self(),
    spawn_link(
	fun () ->
	    ets:insert(Tab, {TRef, self(), timeout}),
	    case timer_recv(Time, tstamp(Time), {dummy, dummy}) of
		stop -> ok;
		timeout -> apply_mfa(MFA)
	    end,
	    ets:delete(Tab, TRef),
	    unlink(TsPid)
	end
    ),
    ok.

% Start an interval timer.
interval_timer(TRef, Time, TrgPid, MFA, Tab) ->
    TsPid = self(),
    spawn_link(
	fun () ->
	    ets:insert(Tab, {TRef, self(), interval}),
	    TrgRef = monitor(process, TrgPid),
	    interval_timer_loop(Time, MFA, {TrgPid, TrgRef}),
	    ets:delete(Tab, TRef),
	    unlink(TsPid)
	end
    ),
    ok.

% Interval timer loop, waits for the given time to expire,
% then applies the given MFA and repeats. Stops without
% applying the MFA when a cancel message is received.
interval_timer_loop(Time, MFA, Trg) ->
    case timer_recv(Time, tstamp(Time), Trg) of
	stop ->
	    stop;
	timeout ->
	    apply_mfa(MFA),
	    interval_timer_loop(Time, MFA, Trg)
    end.

% Receive/wait of a timer. When the given time is greater than
% the maximum timeout, repeats in steps of the maximum timeout.
% When the given time has elapsed, returns timeout. Returns stop
% when a cancel message is received.
timer_recv(Time, TEnd, Trg = {TrgPid, TrgRef}) when Time > ?MAX_TIMEOUT ->
    receive
	{'DOWN', TrgRef, process, TrgPid, _Reason} ->
	    stop;
	cancel ->
	    stop;
	{read, {ReplyTo, Tag}} ->
	    Rem = TEnd - tstamp(),
	    ReplyTo ! {Tag, max(0, Rem div 1000)},
	    timer_recv(ceil(Rem / 1000), TEnd, Trg)
    after ?MAX_TIMEOUT ->
	timer_recv(Time - ?MAX_TIMEOUT, TEnd, Trg)
    end;
timer_recv(Time, TEnd, Trg = {TrgPid, TrgRef}) ->
    receive
	{'DOWN', TrgRef, process, TrgPid, _Reason} ->
	    stop;
	cancel ->
	    stop;
	{read, {ReplyTo, Tag}} ->
	    Rem = TEnd - tstamp(),
	    ReplyTo ! {Tag, max(0, Rem div 1000)},
	    timer_recv(ceil(Rem / 1000), TEnd, Trg)
    after Time ->
	timeout
    end.

% Apply the given MFA.
apply_mfa({erlang, exit, [Name, Reason]}) ->
    catch exit(get_pid(Name), Reason),
    ok;
apply_mfa({?MODULE, send, [To, Msg]}) ->
    To ! Msg,
    ok;
apply_mfa({M, F, A}) ->
    catch spawn(M, F, A),
    ok.

% Get the pid for a registered name.
get_pid(Name) when is_pid(Name) ->
    Name;
get_pid(undefined) ->
    undefined;
get_pid(Name) when is_atom(Name) ->
    get_pid(whereis(Name));
get_pid(_) ->
    undefined.

% Timestamp, current monotonic time in microseconds.
tstamp() ->
    tstamp(0).

tstamp(Offset) ->
    erlang:monotonic_time(microsecond) + 1000 * Offset.

%% This function is for test purposes only; it is used by the test suite.
%% There is a small possibility that there is a mismatch of one entry 
%% between the 2 tables if this call is made when the timer server is 
%% in the middle of a transaction
 
-spec get_status() ->
	{{timer_tab, non_neg_integer()}, {interval_tab, non_neg_integer()}}.

get_status() ->
    #{timeout := T, interval := I} = gen_server:call(timer_server, get_status, infinity),
    {{timer_tab, T + I}, {interval_tab, I}}.
