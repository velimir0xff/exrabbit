defmodule Exrabbit.Consumer do
  defstruct [conn: nil, chan: nil, queue: "", pid: nil, tag: nil]
  alias __MODULE__
  alias Exrabbit.Common
  alias Exrabbit.Connection
  alias Exrabbit.Message
  use Exrabbit.Records

  @doc """
  Create a new consumer bounds to a channel.

  Opens a connection, sets up a channel on it and returns a `Consumer` struct.

  This function declares the exchange and the queue when needed.

  When both `:exchange` and `:queue` or `:new_queue` options are provided, the
  queue will be bound to the exchange.

  ## Options

    * `:chan` - instead of creating a new channel, use the supplied one

    * `:conn_opts` - when no channel is supplied, a new connection will be
      opened; this option allows overriding default connection options

    * `:exchange` - An `exchange_declare` record (in which case it'll be
      declared on the channel) or the name of an existing exchange (with `""`
      referring to the default exchange that is always available).

    * `:queue` - A `queue_declare` record (which will be declared on the
      channel) or the name of an existing queue.

    * `:new_queue` - A string that will be used to declare a new exclusive
      queue on the channel. If an empty string is passed, the name will be
      assigned by the broker.

  """
  def new(options) do
    %Connection{conn: conn, chan: chan} = Common.connection(options)

    exchange = Common.declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = Common.declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    Common.bind_queue(chan, exchange, queue, binding_key)

    %Consumer{conn: conn, chan: chan, queue: queue}
  end

  @doc """
  Close the connection initiated by the consumer.
  """
  def shutdown(%Consumer{conn: conn, chan: chan}) do
    Connection.close(%Connection{conn: conn, chan: chan})
  end

  @doc """
  Subscribe a consumer to a queue.

  Returns a new `Consumer` struct that encapsulates the pid of the subcribed
  process and an internal tag that can be used to unsubscribe from the queue.

  If the function is passed, a service process will be spawned inside of which
  it will be invoked.
  """
  def subscribe(consumer=%Consumer{chan: chan, queue: queue}, target, options \\ []) do
    simple_messages = Keyword.get(options, :simple, true)
    pid = case target do
      pid when is_pid(pid) -> pid
      fun when is_function(fun, 1) ->
        spawn_service_proc(fun, simple_messages)
    end
    tag = do_subscribe(chan, queue, pid, options)
    %Consumer{consumer | tag: tag, pid: pid}
  end

  defp do_subscribe(chan, queue, pid, options) do
    method = basic_consume(
      queue: queue,
      consumer_tag: Keyword.get(options, :consumer_tag, ""),
      no_local: Keyword.get(options, :no_local, false),
      no_ack: Keyword.get(options, :no_ack, true),
      exclusive: Keyword.get(options, :exclusive, false),
      arguments: Keyword.get(options, :extra, []),
    )
    basic_consume_ok(consumer_tag: consumer_tag) =
      :amqp_channel.subscribe(chan, method, pid)
    consumer_tag
  end

  @doc """
  Unsubscribe from the queue.

  Returns a new `Consumer` struct.
  """
  def unsubscribe(consumer=%Consumer{chan: chan, tag: tag}) do
    basic_cancel_ok() = :amqp_channel.call(chan, basic_cancel(consumer_tag: tag))
    %Consumer{consumer | tag: nil, pid: nil}
  end

  @doc """
  Blocks the current process until a new message arrives.

  Returns `{:ok, <message>}` or `{:error, <reason>}`.
  """
  def get_body(%Consumer{chan: chan, queue: queue}) do
    case do_get(chan, queue, true) do
      nil -> nil
      {basic_get_ok(), amqp_msg(payload: body)} -> {:ok, body}
    end
  end

  def get(%Consumer{chan: chan, queue: queue}, options \\ []) do
    no_ack = Keyword.get(options, :no_ack, true)

    case do_get(chan, queue, no_ack) do
      nil -> nil
      {basic_get_ok(delivery_tag: dtag, redelivered: rflag, exchange: exchange,
                    routing_key: key, message_count: cnt),
                    amqp_msg(props: props, payload: body)} ->
        msg = %Message{
          delivery_tag: dtag, redelivered: rflag, exchange: exchange,
          routing_key: key, message_count: cnt, body: body, props: props,
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

  def ack(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.ack(chan, tag, opts)
  end

  def nack(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.nack(chan, tag, opts)
  end

  def reject(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.reject(chan, tag, opts)
  end

  ###

  defp spawn_service_proc(fun, true) do
    spawn_link(fn -> service_loop_simple(fun) end)
  end

  defp spawn_service_proc(fun, false) do
    spawn_link(fn -> service_loop(fun) end)
  end

  defp service_loop_simple(fun) do
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
    receive do
      basic_consume_ok()=x ->
        fun.(x)
        service_loop(fun)
      basic_cancel_ok()=x ->
        fun.(x)
        :ok
      {basic_deliver(consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
                     exchange: exchange, routing_key: key),
                     amqp_msg(props: props, payload: body)} ->
        msg = %Message{
          consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
          exchange: exchange, routing_key: key, body: body, props: props,
        }
        fun.(msg)
        service_loop(fun)

      other ->
        raise "Unexpected message #{inspect other}"
    end
  end
end
