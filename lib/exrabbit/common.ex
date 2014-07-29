defmodule Exrabbit.Common do
  @moduledoc false

  use Exrabbit.Records

  def declare_exchange(chan, exchange_declare(exchange: name)=x) do
    exchange_declare_ok() = :amqp_channel.call(chan, x)
    name
  end

  def declare_exchange(_chan, name) when is_binary(name) do
    name
  end

  def declare_queue(_chan, nil, nil) do
    ""
  end

  def declare_queue(chan, queue_declare()=q, nil) do
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, q)
    name
  end

  def declare_queue(_chan, name, nil) when is_binary(name) do
    name
  end

  def declare_queue(chan, nil, name) when is_binary(name) do
    q = queue_declare(queue: name, exclusive: true)
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, q)
    name
  end

  def declare_queue(_, _, _) do
    raise "Passing both :queue and :new_queue to Producer.new is an error"
  end

  def bind_queue(_chan, "", _queue, _binding_key), do: nil
  def bind_queue(_chan, _exchange, "", _binding_key), do: nil
  def bind_queue(chan, exchange, queue, binding_key) do
    b = queue_bind(exchange: exchange, queue: queue, routing_key: binding_key || "")
    queue_bind_ok() = :amqp_channel.call(chan, b)
    nil
  end
end
