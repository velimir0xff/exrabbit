defmodule Exrabbit.Consumer do
  @moduledoc """
  Consumer abstraction over raw connection, channel, and queue.
  """

  defstruct [conn: nil, chan: nil, queue: "", pid: nil, tag: nil]
  alias __MODULE__
  alias Exrabbit.Common
  alias Exrabbit.Connection
  alias Exrabbit.Message
  use Exrabbit.Records

  @typep consumer_tag :: binary
  @typep delivery_tag :: binary
  @typep simple_message :: {:begin, consumer_tag}
                         | {:end, consumer_tag}
                         | {:msg, {consumer_tag, delivery_tag}, binary}
  @typep full_message :: Exrabbit.Records.basic_consume_ok
                       | Exrabbit.Records.basic_cancel_ok
                       | {Exrabbit.Records.basic_deliver, Exrabbit.Records.amqp_msg}

  @doc """
  Create a new consumer bound to a channel.

  Opens a connection, sets up a channel on it and returns a `Consumer` struct.

  This function declares the exchange and the queue when needed.

  When both `:exchange` and `:queue` or `:new_queue` options are provided, the
  queue will be bound to the exchange.

  ## Options

    * `:chan` - instead of creating a new channel, use the supplied one.

    * `:conn_opts` - when no channel is supplied, a new connection will be
      opened; this option allows overriding default connection options, see
      `Exrabbit.Connection.open` for more info.

    * `:exchange` - an `exchange_declare` record (in which case it'll be
      declared on the channel) or the name of an existing exchange (with `""`
      referring to the default exchange that is always available).

    * `:queue` - a `queue_declare` record (which will be declared on the
      channel) or the name of an existing queue.

    * `:new_queue` - a string that will be used to declare a new exclusive
      queue on the channel. If an empty string is passed, the name will be
      assigned by the broker.

    * `:binding_key` - the binding key used when binding the queue to the
      exchange.

  """
  @spec new(Keyword.t) :: %Consumer{}
  def new(options) do
    %Connection{conn: conn, chan: chan} = Common.connection(options)

    exchange = Common.declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = Common.declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    Common.bind_queue(chan, exchange, queue, binding_key)

    %Consumer{conn: conn, chan: chan, queue: queue}
  end

  @doc """
  Close the previously established connection.
  """
  @spec shutdown(%Consumer{}) :: :ok
  def shutdown(%Consumer{conn: conn, chan: chan}) do
    Connection.close(%Connection{conn: conn, chan: chan})
  end

  @doc """
  Subscribe consumer to a queue.

  Returns a new `Consumer` struct that encapsulates the pid of the subcribed
  process and an internal tag that can be used to unsubscribe from the queue.

  If a function is passed as the target, a service process will be spawned
  inside of which it will be invoked.

  ## Options

    * `simple: <boolean>` - when `true` (default), the simple message format
      will be used for incoming messages; when `false`, the full message format
      will be used which uses records provided by the Erlang client.

      The simple message format is comprised of the following 3 messages:

        - `{:begin, ctag}`
        - `{:end, ctag}`
        - `{:msg, {ctag, dtag}, body}`

      where `ctag` is the consumer tag set by the broker, `dtag` is the
      delivery tag which can be used to acknowledge the message, and `body` is
      the message body.

      The full message format is defined by the following 3 messages:

        - `basic_consume_ok()`
        - `basic_cancel_ok()`
        - `{basic_deliver(), amqp_msg()}`

      These are all records imported from the Erlang client. The last message
      can be passed to `Exrabbit.Util.parse_message/1` to get an
      `%Exrabbit.Message{}` struct back.

    * any options defined in the `basic_consume` record from the Erlang client
      with one exception: instead of `:arguments` use the key `:extra` to pass
      any additional arguments supported by RabbitMQ extensions.

  """
  @spec subscribe(%Consumer{}, pid | ((simple_message | full_message) -> any)) :: %Consumer{}
  @spec subscribe(%Consumer{}, pid | ((simple_message | full_message) -> any), Keyword.t) :: %Consumer{}
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

  Returns a new `Consumer` struct. The channel owned by the consumer is kept
  open.
  """
  @spec unsubscribe(%Consumer{}) :: %Consumer{}
  def unsubscribe(consumer=%Consumer{tag: nil}) do
    consumer
  end

  def unsubscribe(consumer=%Consumer{chan: chan, tag: tag}) do
    basic_cancel_ok() = :amqp_channel.call(chan, basic_cancel(consumer_tag: tag))
    %Consumer{consumer | tag: nil, pid: nil}
  end

  @doc """
  Block until a new message arrives and return its body.

  Returns `{:ok, <message body>}` or `nil`.
  """
  def get_body(%Consumer{chan: chan, queue: queue}) do
    case do_get(chan, queue, true) do
      nil -> nil
      {basic_get_ok(), amqp_msg(payload: body)} -> {:ok, body}
    end
  end

  @doc """
  Block until a new message arrives and return it.

  Returns `{:ok, %Message{}}` or `nil`.
  """
  def get(%Consumer{chan: chan, queue: queue}, options \\ []) do
    no_ack = Keyword.get(options, :no_ack, true)

    case do_get(chan, queue, no_ack) do
      nil -> nil
      {basic_get_ok(), amqp_msg()}=incoming_msg ->
        msg = Exrabbit.Util.parse_message(incoming_msg)
        {:ok, msg}
    end
  end

  @doc """
  Acknowledge received message.

  The consumer has to be created with `no_ack: false` in order to use this
  function.

  Calls `Exrabbit.Channel.ack/3` under the hood.
  """
  @spec ack(%Consumer{}, %Message{}) :: :ok
  @spec ack(%Consumer{}, %Message{}, Keyword.t) :: :ok
  def ack(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.ack(chan, tag, opts)
  end

  @doc """
  Reject received message.

  The consumer has to be created with `no_ack: false` in order to use this
  function.

  Calls `Exrabbit.Channel.reject/3` under the hood.
  """
  @spec reject(%Consumer{}, %Message{}) :: :ok
  @spec reject(%Consumer{}, %Message{}, Keyword.t) :: :ok
  def reject(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.reject(chan, tag, opts)
  end

  @doc """
  Reject one or more received messages.

  The consumer has to be created with `no_ack: false` in order to use this
  function.

  Calls `Exrabbit.Channel.nack/3` under the hood.
  """
  @spec nack(%Consumer{}, %Message{}) :: :ok
  @spec nack(%Consumer{}, %Message{}, Keyword.t) :: :ok
  def nack(%Consumer{chan: chan}, %Message{delivery_tag: tag}, opts \\ []) do
    Exrabbit.Channel.nack(chan, tag, opts)
  end

  ###

  defp do_get(chan, queue, no_ack) do
    case :amqp_channel.call(chan, basic_get(queue: queue, no_ack: no_ack)) do
      basic_get_empty() -> nil
      {basic_get_ok(), _content}=msg -> msg
    end
  end

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
      {basic_deliver(consumer_tag: ctag, delivery_tag: dtag), amqp_msg(payload: body)} ->
        fun.({:msg, {ctag, dtag}, body})
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
      {basic_deliver(), amqp_msg()}=msg ->
        fun.(msg)
        service_loop(fun)

      other ->
        raise "Unexpected message #{inspect other}"
    end
  end
end
