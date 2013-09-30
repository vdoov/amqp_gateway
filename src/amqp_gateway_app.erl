-module(amqp_gateway_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%API:
-export([
	initialize_connection/1,
	initialize_and_subscribe/5, 
	declare_exchange/2,
	publish/2
	]).
%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    amqp_gateway_sup:start_link().

stop(_State) ->
    ok.
    
initialize_and_subscribe(AMQPHost, AMQPExchange, AMQPExchangeType, AMQPQueue, MessageProcessor) ->
  gen_server:call(amqp_subscriber, {init_and_subscribe, AMQPHost, AMQPExchange, AMQPExchangeType, AMQPQueue, MessageProcessor}).    

declare_exchange(ExchangeName, ExchangeType) ->
  gen_server:call(amqp_subscriber, {declare_exchange, ExchangeName, ExchangeType}).

initialize_connection(Host) ->
  gen_server:call(amqp_subscriber, {init_amqp_connection, Host}).

publish(ExchangeName, Payload) ->
  gen_server:call(amqp_subscriber, {publish, ExchangeName, Payload}).