{application, amqp_gateway,
 [
  {description, "Gateway to RabbitMQ AMQP Message Bus. Used to publish and subscribe for EMB Messages."},
  {vsn, "0.0.1"},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib
                 ]},
  {mod, { amqp_gateway_app, []}},
  {modules, [
    amqp_gateway_app,
    amqp_gateway_sup,
    amqp_subscriber
  ]},
  {env, []}
 ]}.
