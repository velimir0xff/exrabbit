defmodule Exrabbit.Util do
  use Exrabbit.Records

  def parse_message({
    basic_deliver(consumer_tag: ctag, delivery_tag: dtag,
                  redelivered: rflag, exchange: exchange, routing_key: key),
    amqp_msg(props: props, payload: body)
  }) do
    %Exrabbit.Message{
      consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
      exchange: exchange, routing_key: key, body: body, props: props,
    }
  end
end
