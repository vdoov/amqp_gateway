%%%-------------------------------------------------------------------
%%% @author Alex Vdovin <2v2odmail@gmail.com>
%%% @copyright 2013 Alex Vdovin
%%% @doc AMQP Messags subscriber
%%% @end
%%%-------------------------------------------------------------------

-module(amqp_gateway_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  RestartStrategy = {one_for_one, 0, 1},
  AMQPSubscriber = {amqp_subscriber, {amqp_subscriber, start_link, []}, permanent, 5000, worker, [amqp_subscriber]},
  {ok, { RestartStrategy, [AMQPSubscriber]} }.
