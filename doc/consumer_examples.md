Basic Consumer API
==================

## Consumer acknowledgements

Ack'ing a message means invoking one of `ack`, `nack`, or `reject` methods on a
channel.

With the basic API, function on `Exrabbit.Channel` can be used for this:

```elixir
conn = %Exrabbit.Connection{chan: chan} = Exrabbit.Connection.open()

subscription_fun = fn
  {:msg, tag, message} ->
    IO.inspect message
    Exrabbit.Channel.ack(chan, tag)
  _ -> nil
end

# the :no_ack options lets us indicate that we will acknowledge received
# messages
consumer =
  Consumer.new(chan: chan, exchange: exchange, queue: queue)
  |> Consumer.subscribe(subscription_fun, no_ack: false)

# ...

Exrabbit.Connection.close(conn)
```

## Consumer DSL

When using `Exrabbit.Consumer.DSL`, messages can still be ack'ed explicitly via
`Exrabbit.Consumer.{ack|nack|reject}` or implicitly by returning a properly
tagged tuple from the message handler:

```elixir
defmodule MyConsumer do
  use Exrabbit.Consumer.DSL, no_ack: false

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  init [] do
    {:ok, nil}
  end

  on %Message{exchange: "my_exchange", message: body}, nil do
    # do something with the message
    # ...

    # implicit ack
    {:ack, nil}
  end

  on _, nil do
    # implicit reject
    {:reject, nil}
  end
end
```
