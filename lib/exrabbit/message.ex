defmodule Exrabbit.Message do
  use Exrabbit.Records

  defstruct [
    consumer_tag: nil,
    delivery_tag: nil,
    redelivered: false,
    exchange: "",
    routing_key: "",
    message_count: nil,
    message: "",
    props: pbasic(),
  ]
end

