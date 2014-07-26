defmodule Exrabbit.Consumer do
  defstruct [channel: nil, queue: ""]
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

    * `:subscribe` - Subsribe the given process (identified by pid or
      registered name) to receive messages from the queue. Allowed values:
      `<pid or atom>` or a value returned from
      `Exrabbit.Consumer.process(pid)`.

  """
  def new(chan, options) do
    exchange = Common.declare_exchange(chan, Keyword.get(options, :exchange, ""))
    queue = Common.declare_queue(chan, Keyword.get(options, :queue, nil), Keyword.get(options, :new_queue, nil))

    binding_key = Keyword.get(options, :binding_key, nil)
    Common.bind_queue(chan, exchange, queue, binding_key)

    consumer = %Consumer{channel: chan, queue: queue}
    if pid=Keyword.get(options, :subscribe, false) do
      subscribe(consumer, pid)
    end
    consumer
  end

  def subscribe(consumer=%Consumer{channel: chan, queue: queue}, pid) do
    Exrabbit.Channel.subscribe(chan, queue, pid)
    consumer
  end
end
