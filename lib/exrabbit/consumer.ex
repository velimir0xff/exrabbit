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

    * `:subscribe` - Subsribe a process (identified by pid or registered name)
      or a function to receive messages from the queue.

    * `:into` - Feed incoming messages into the given process, stream, or
      function as they arrive.

  ## Subscription semantics

  When supplying the `:subscribe` option or calling `Consumer.subscribe/2`, the
  target process will begin receiving messages from the queue.

  Supplying the `:into` option or calling `Consumer.consume/2` will block the
  calling process until the message queue is deleted or the connection is
  closed.

  """
  def new(chan, options) do
    exchange = Common.declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = Common.declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    Common.bind_queue(chan, exchange, queue, binding_key)

    consumer = %Consumer{channel: chan, queue: queue}
    validate_subscribe_options(options)
    cond do
      pid=Keyword.get(options, :subscribe, false) ->
        subscribe(consumer, pid)
      sink=Keyword.get(options, :into, nil) ->
        consume(consumer, sink)
      true -> consumer
    end
  end

  @doc """
  Subscribe a consumer to a queue.

  Returns a new `Consumer` struct that encapsulates the pid of the subcribed
  process and an internal tag that can be used to unsubscribe from the queue.

  If the function is passed, a service process will be spawned inside of which
  it will be invoked.
  """
  def subscribe(consumer=%Consumer{channel: chan, queue: queue}, target) do
    pid = case target do
      pid when is_pid(pid) -> pid
      fun when is_function(fun, 1) ->
        spawn_service_proc(fun)
    end
    tag = Exrabbit.Channel.subscribe(chan, queue, pid)
    %Consumer{consumer | tag: tag, pid: pid}
  end

  @doc """
  Unsubscribe from the queue.

  Returns a new `Consumer` struct.
  """
  def unsubscribe(consumer=%Consumer{channel: chan, tag: tag}) do
    basic_cancel_ok() = :amqp_channel.call(chan, basic_cancel(consumer_tag: tag))
    %Consumer{consumer | tag: nil, pid: nil}
  end

  def consume(consumer, into: pid) when is_pid(pid) do
    IO.puts "FLUSHING MESSAGES INTO #{inspect pid}"
    :ok
  end

  def consume(consumer, into: fun) when is_function(fun, 1) do
    IO.puts "FLUSHING MESSAGES INTO #{inspect fun}"
    :ok
  end

  def consume(consumer, into: stream) do
    if nil?(Collectable.impl_for(stream)) do
      raise "Expected a stream in consume(). Got #{inspect stream}"
    end
    IO.puts "FLUSHING MESSAGES INTO #{inspect stream}"
    :ok
  end

  ###

  defp validate_subscribe_options(options) do
    if options[:subscribe] && options[:into] do
      raise "Only one of :subscribe or :into can be used at once"
    end
  end

  defp spawn_service_proc(fun) do
    spawn_link(fn -> service_loop(fun) end)
  end

  defp service_loop(fun) do
    receive do
      Exrabbit.Defs.basic_consume_ok() ->
        fun.(:start)
        service_loop(fun)
      Exrabbit.Defs.basic_cancel_ok() ->
        fun.(:end)
        :ok
      {Exrabbit.Defs.basic_deliver(), Exrabbit.Defs.amqp_msg(payload: body)} ->
        fun.({:msg, body})
        service_loop(fun)
    end
  end
end
