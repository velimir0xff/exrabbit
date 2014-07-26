defmodule Exrabbit.Producer do
  use Exrabbit.Defs

  defstruct [channel: nil, exchange: "", routing_key: ""]
  alias __MODULE__

  @doc """
  This function declares the exchange and the queue when needed.

  When both `:exchange` and `:queue` or `:new_queue` options are provided, the
  queue will be bound to the exchange.

  ## Options

    * `:exchange` - An `exchange_declare` record (in which case it'll be
      declared on the channel) or the name of an existing exchange (with `""`
      referring to the default exchange that is always available).

    * `:queue` - A `queue_declare` record (which will be declared on the
      channel) or the name of an existing queue.

    * `:new_queue` - A string that will be used to declare a new exclusive
      queue on the channel. If an empty string is passed, the name will be
      assigned by the broker.

  """
  def new(chan, options) do
    exchange = declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    bind_queue(chan, exchange, queue, binding_key)

    routing_key = choose_routing_key(exchange, queue, binding_key)
    %Producer{channel: chan, exchange: exchange, routing_key: routing_key}
  end

  def publish(%Producer{channel: chan, exchange: x, routing_key: key}, message, options \\ []) do
    validate_publish_options(options)
    new_options = Keyword.merge([exchange: x, routing_key: key], options)
    Exrabbit.Channel.publish(chan, message, new_options)
  end

  ###

  defp declare_exchange(chan, exchange_declare(exchange: name)=x) do
    exchange_declare_ok() = :amqp_channel.call(chan, x)
    name
  end

  defp declare_exchange(_chan, name) when is_binary(name) do
    name
  end

  defp declare_queue(_chan, nil, nil) do
    ""
  end

  defp declare_queue(chan, queue_declare()=q, nil) do
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, q)
    name
  end

  defp declare_queue(_chan, name, nil) when is_binary(name) do
    name
  end

  defp declare_queue(chan, nil, name) when is_binary(name) do
    q = queue_declare(queue: name, exclusive: true)
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, q)
    name
  end

  defp declare_queue(_, _, _) do
    raise "Passing both :queue and :new_queue to Producer.new is an error"
  end

  defp bind_queue(_chan, "", _queue, _binding_key), do: nil

  defp bind_queue(chan, exchange, queue, binding_key) do
    b = queue_bind(exchange: exchange, queue: queue, routing_key: binding_key || "")
    queue_bind_ok() = :amqp_channel.call(chan, b)
    nil
  end

  defp choose_routing_key(_exchange, queue, nil) do
    queue
  end

  defp choose_routing_key(_exchange, _queue, binding_key) do
    binding_key
  end

  defp validate_publish_options(options) do
    case Enum.partition(options, fn {k, _} -> k in [:exchange, :routing_key] end) do
      {good, []} -> good
      {_, bad} -> raise "Bad options to publish(): #{inspect bad}"
    end
  end
end
