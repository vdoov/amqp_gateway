-module(amqp_gateway_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, initialize_and_subscribe/5]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    amqp_gateway_sup:start_link().

stop(_State) ->
    ok.
    
initialize_and_subscribe(AMQPHost, AMQPExchange, AMQPExchangeType, AMQPQueue, MessageProcessor) ->
  gen_server:call(amqp_subscriber, {init_amqp_connection, AMQPHost, AMQPExchange, AMQPExchangeType, AMQPQueue, MessageProcessor}).    