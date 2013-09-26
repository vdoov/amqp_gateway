%%%-------------------------------------------------------------------
%%% @author Alex Vdovin <2v2odmail@gmail.com>
%%% @copyright 2013 Alex Vdovin
%%% @doc RabbitMQ EMB Gateway Process
%%% Handles RabbitMQ Connection, AMQP Channel, Exchanhe and QUEUE.
%%% Subscribes for events and pushes them for further processing.
%%% @end
%%%-------------------------------------------------------------------
-module(amqp_subscriber).

-behaviour(gen_server).

-include("amqp_client.hrl").

%% API
-export([
    start_link/0,
    stop/0,
    confirm/1,
    confirm_by_tag/1,
    get_messages_cnt/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3]).
  
-record(amqp, {amqp_connection, amqp_channel, amqp_consumer_tag}).
-record(state, {amqp=#amqp{}, message_processor=undefined, messages_since_last_metrics_call=0, messages_confirmed_since_last_metrics_call=0}).

-define(AMQP_QUEUE_NAME, <<"deviceter_logservice">>).
-define(AMQP_EXCHANGE_NAME, <<"unknown">>).
-define(AMQP_SERVER_HOST, "cloudserver-0").
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Returns the number of received messages from EMB QUEUE 
%% since last metrics read.
%% Resets the counter after this reading.
%% @spec get_messages_cnt() -> Num::integer()
%% @end
%%--------------------------------------------------------------------
get_messages_cnt() ->
  gen_server:call(?MODULE, get_messages_cnt).

%%--------------------------------------------------------------------
%% @doc Confirms that AMQP message handled by Pid is handled.
%% Sends the signal to terminate the Pid as its job is done.
%% This confirm is called when the data is already stored in HBase
%% @spec confirm(Pid) -> ok
%% where
%% Pid = pid()
%% @end
%%--------------------------------------------------------------------
confirm(Pid) ->
  {ok, Tag} = message_proc:get_confirm_tag(Pid),
  gen_server:cast(?MODULE, {confirm, Tag}),
  message_proc:stop(Pid),
  ok.

confirm_by_tag(Tag) ->
  gen_server:cast(?MODULE, {confirm, Tag}),
  ok.

%%--------------------------------------------------------------------
%% @doc Starts the server.
%%
%% @spec start_link() -> {ok, Pid}
%% where
%% Pid = pid()
%% @end
%%--------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc Stops the server.
%% @spec stop() -> ok
%% @end
%%--------------------------------------------------------------------
stop() ->
  gen_server:cast(?MODULE, stop).

%%%===================================================================
%%% Internal Functions
%%%===================================================================
init_amqp_connection(AMQPHost, AMQPExchange, AMQPExchangeType, AMQPQueue) ->
  case amqp_connection:start(#amqp_params_network{host=AMQPHost}) of
    {ok, AMQPConnection} ->
      %%RabbitMQ Channel Declaration:
      {ok, AMQPChannel} = amqp_connection:open_channel(AMQPConnection),
      
      %%Declare RabbitMQ Log Exchange:
      AMQPExchangeDeclaration = #'exchange.declare'{exchange = AMQPExchange, type=AMQPExchangeType},
      #'exchange.declare_ok'{} = amqp_channel:call(AMQPChannel, AMQPExchangeDeclaration),
      
      %%Declare RabbitMQ Queue:
      AMQPQueueDeclaration = #'queue.declare'{queue = AMQPQueue},
      #'queue.declare_ok'{} = amqp_channel:call(AMQPChannel, AMQPQueueDeclaration),
      
      %%Bind AMQP Channel with Queue:
      AMQPBindingDeclaration = #'queue.bind'{queue = AMQPQueue,
				  exchange    = AMQPExchange},
      #'queue.bind_ok'{} = amqp_channel:call(AMQPChannel, AMQPBindingDeclaration),
      
      %%Subscribe for messages:
      SubDeclaration = #'basic.consume'{queue = AMQPQueue},
      #'basic.consume_ok'{consumer_tag = AMQPConsumerTag} = amqp_channel:call(AMQPChannel, SubDeclaration),
      
      AMQP = #amqp{amqp_connection=AMQPConnection, amqp_channel=AMQPChannel, amqp_consumer_tag=AMQPConsumerTag},
      {ok, AMQP};
    {error, Error} ->
      {error, Error}
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}, infinity}.
    %case init_amqp_connection() of 
    %{ok, AMQP} ->
    %  {ok, #state{amqp=AMQP}, infinity};
    %{error, Error} ->
    %  {stop, Error}
    %end.

handle_call({init_amqp_connection, Host, Exchange, ExchangeType, Queue, MessageProcessor}, _FROM, State) ->
  case init_amqp_connection(Host, Exchange, ExchangeType, Queue) of 
    {ok, AMQP} ->
      {reply, ok, State#state{amqp=AMQP, message_processor=MessageProcessor}};
    {error, Error} ->
      {reply, {error, Error}, State}
  end;
handle_call(get_messages_cnt, _From, #state{messages_since_last_metrics_call=MsgCnt, messages_confirmed_since_last_metrics_call=ConfirmedCnt} = State) ->
  NewState=State#state{messages_since_last_metrics_call=0, messages_confirmed_since_last_metrics_call=0},
  {reply, {ok, {MsgCnt, ConfirmedCnt}}, NewState};

handle_call(get_server_state, _From, State) ->
  {reply, State, State};
handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast({confirm, Tag}, #state{amqp=AMQP, messages_confirmed_since_last_metrics_call=ConfirmedCnt} = State) ->
  %% Ack the message
  amqp_channel:cast(AMQP#amqp.amqp_channel, #'basic.ack'{delivery_tag = Tag}),
  {noreply, State#state{messages_confirmed_since_last_metrics_call=ConfirmedCnt + 1}};

handle_cast(increment_msg_counter, #state{messages_since_last_metrics_call=OldMsgCnt} = State) ->
  {noreply, State#state{messages_since_last_metrics_call=OldMsgCnt + 1}};
  
handle_cast(stop, State) ->
  {stop, normal, State};    
handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(timeout, State) ->
  {noreply, State, infinity};

%%RabbitMQ Events falls here:
handle_info(Info, State) ->
  case Info of
    %% This is the confirm subscription message:
    #'basic.consume_ok'{} ->
      lager:info("AMQP Subscriber is starting to consume messages"),
      ok;
    #'basic.cancel_ok'{} ->
      lager:info("Subscription is canceled"),
      ok;
    {#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload=Payload}} ->
    
      gen_server:cast(?MODULE, increment_msg_counter),
      MessageProcessor = State#state.message_processor,
      MessageProcessor({Payload, Tag}),
%      message_processor:process_message({Payload, Tag}),
      
      ok;
    Other ->
      lager:warning("Unknown event in AMQP Subscriber handle_info: ~p", [Other]),
      ok
  end,
  {noreply, State}.
  
terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.