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
  alias __MODULE__

  def ack(%Message{delivery_tag: tag}, chan, opts \\ []) do
    Exrabbit.Channel.ack(chan, tag, opts)
  end

  def nack(%Message{delivery_tag: tag}, chan, opts \\ []) do
    Exrabbit.Channel.nack(chan, tag, opts)
  end

  def reject(%Message{delivery_tag: tag}, chan, opts \\ []) do
    Exrabbit.Channel.reject(chan, tag, opts)
  end
end

