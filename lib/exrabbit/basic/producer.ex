defmodule Exrabbit.Producer do
  defstruct [channel: nil, exchange: "", routing_key: ""]
  alias __MODULE__
  alias Exrabbit.Common
  use Exrabbit.Records

  @doc """
  Create a new producer bound to a channel.

  Returns a `Producer` struct.

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
    exchange = Common.declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = Common.declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    Common.bind_queue(chan, exchange, queue, binding_key)

    routing_key = choose_routing_key(exchange, queue, binding_key)
    %Producer{channel: chan, exchange: exchange, routing_key: routing_key}
  end

  def publish(%Producer{channel: chan, exchange: x, routing_key: key}, message, options \\ []) do
    validate_publish_options(options)
    options = Keyword.merge([exchange: x, routing_key: key], options)

    exchange = Keyword.get(options, :exchange, "")
    routing_key = Keyword.get(options, :routing_key, "")
    wait = Keyword.get(options, :await_confirm, false)
    timeout = Keyword.get(options, :timeout, nil)
    publish(chan, exchange, routing_key, message, wait, timeout)
  end

  defp publish(chan, exchange, routing_key, message, false, _) do
    do_publish(chan, exchange, routing_key, message)
  end

  defp publish(chan, exchange, routing_key, message, true, timeout) do
    :ok = do_publish(chan, exchange, routing_key, message)
    if timeout do
      Exrabbit.Channel.await_confirms(chan, timeout)
    else
      Exrabbit.Channel.await_confirms(chan)
    end
  end

  defp do_publish(chan, exchange, routing_key, message) do
    method = basic_publish(exchange: exchange, routing_key: routing_key)
    msg = amqp_msg(payload: message)
    :amqp_channel.call(chan, method, msg)
  end

  ###

  defp choose_routing_key(_exchange, queue, nil) do
    queue
  end

  defp choose_routing_key(_exchange, _queue, binding_key) do
    binding_key
  end

  defp validate_publish_options(options) do
    case Enum.partition(options, fn {k, _} -> k in [:exchange, :routing_key, :await_confirm, :timeout] end) do
      {good, []} -> good
      {_, bad} -> raise "Bad options to publish(): #{inspect bad}"
    end
  end
end

defimpl Collectable, for: Exrabbit.Producer do
  def into(producer) do
    {nil, fn
      _, {:cont, bin} -> Exrabbit.Producer.publish(producer, bin)
      _, :done -> producer
      _, :halt -> nil
    end}
  end

  def empty(_) do
    raise "empty() is not supported by Exrabbit.Producer"
  end
end
