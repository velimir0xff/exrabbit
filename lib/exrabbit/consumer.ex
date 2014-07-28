defmodule Exrabbit.Message do
  defstruct [
    consumer_tag: nil,
    delivery_tag: nil,
    redelivered: false,
    exchange: "",
    routing_key: "",
    message_count: nil,
    message: nil,
  ]
end

defmodule Exrabbit.Consumer do
  use Exrabbit.Defs

  defstruct [channel: nil, queue: "", pid: nil, tag: nil]
  alias __MODULE__
  alias Exrabbit.Common

  @doc """
  Create a new consumer bounds to a channel.

  Returns a new `Consumer` struct.

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

    %Consumer{channel: chan, queue: queue}
  end

  @doc """
  Subscribe a consumer to a queue.

  Returns a new `Consumer` struct that encapsulates the pid of the subcribed
  process and an internal tag that can be used to unsubscribe from the queue.

  If the function is passed, a service process will be spawned inside of which
  it will be invoked.
  """
  def subscribe(consumer=%Consumer{channel: chan, queue: queue}, target, options \\ []) do
    simple_messages = Keyword.get(options, :simple, true)
    pid = case target do
      pid when is_pid(pid) -> pid
      fun when is_function(fun, 1) ->
        spawn_service_proc(fun, simple_messages)
    end
    tag = do_subscribe(chan, queue, pid)
    %Consumer{consumer | tag: tag, pid: pid}
  end

  defp do_subscribe(chan, queue, pid) do
    method = basic_consume(queue: queue)
    basic_consume_ok(consumer_tag: consumer_tag) =
      :amqp_channel.subscribe(chan, method, pid)
    consumer_tag
  end

  @doc """
  Unsubscribe from the queue.

  Returns a new `Consumer` struct.
  """
  def unsubscribe(consumer=%Consumer{channel: chan, tag: tag}) do
    basic_cancel_ok() = :amqp_channel.call(chan, basic_cancel(consumer_tag: tag))
    %Consumer{consumer | tag: nil, pid: nil}
  end

  @doc """
  Blocks the current process until a new message arrives.

  Returns `{:ok, <message>}` or `{:error, <reason>}`.
  """
  def get(%Consumer{channel: chan, queue: queue}, options \\ []) do
    import Exrabbit.Defs

    no_ack = Keyword.get(options, :no_ack, true)

    case do_get(chan, queue, no_ack) do
      nil -> {:error, :empty_response}
      {basic_get_ok(), amqp_msg(payload: body)} ->
        {:ok, body}
    end
  end

  def get_full(%Consumer{channel: chan, queue: queue}, options \\ []) do
    import Exrabbit.Defs

    no_ack = Keyword.get(options, :no_ack, true)

    case do_get(chan, queue, no_ack) do
      nil -> {:error, :empty_response}
      {basic_get_ok(delivery_tag: dtag, redelivered: rflag, exchange: exchange,
                    routing_key: key, message_count: cnt), amqp_msg()=payload} ->
        msg = %Exrabbit.Message{
          delivery_tag: dtag, redelivered: rflag, exchange: exchange,
          routing_key: key, message_count: cnt, message: payload,
        }
        {:ok, msg}
    end
  end

  defp do_get(chan, queue, no_ack) do
    case :amqp_channel.call(chan, basic_get(queue: queue, no_ack: no_ack)) do
      basic_get_empty() -> nil
      {basic_get_ok(), _content}=msg -> msg
    end
  end

  ###

  defp spawn_service_proc(fun, true) do
    spawn_link(fn -> service_loop_simple(fun) end)
  end

  defp spawn_service_proc(fun, false) do
    spawn_link(fn -> service_loop(fun) end)
  end

  defp service_loop_simple(fun) do
    import Exrabbit.Defs
    receive do
      basic_consume_ok(consumer_tag: tag) ->
        fun.({:begin, tag})
        service_loop_simple(fun)
      basic_cancel_ok(consumer_tag: tag) ->
        fun.({:end, tag})
        :ok
      {basic_deliver(consumer_tag: tag), amqp_msg(payload: body)} ->
        fun.({:msg, tag, body})
        service_loop_simple(fun)
    end
  end

  defp service_loop(fun) do
    import Exrabbit.Defs
    receive do
      basic_consume_ok()=x ->
        fun.(x)
        service_loop(fun)
      basic_cancel_ok()=x ->
        fun.(x)
        :ok
      {basic_deliver(consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
                     exchange: exchange, routing_key: key), amqp_msg()=payload} ->
        msg = %Exrabbit.Message{
          consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
          exchange: exchange, routing_key: key, message: payload,
        }
        fun.(msg)
        service_loop(fun)

      other ->
        raise "Unexpected message #{inspect other}"
    end
  end
end
