defmodule Exrabbit.Util do
  use Exrabbit.Records

  alias Exrabbit.Message

  def parse_message({
    basic_deliver(consumer_tag: ctag, delivery_tag: dtag,
                  redelivered: rflag, exchange: exchange, routing_key: key),
    amqp_msg(props: props, payload: body)
  }) do
    %Message{
      consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
      exchange: exchange, routing_key: key, body: body, props: props,
    }
  end

  def parse_message({
    basic_get_ok(delivery_tag: dtag,
                 redelivered: rflag, exchange: exchange, routing_key: key,
                 message_count: cnt),
    amqp_msg(props: props, payload: body)
  }) do
    %Message{
      delivery_tag: dtag, redelivered: rflag, exchange: exchange,
      routing_key: key, message_count: cnt, body: body, props: props,
    }
  end
end
