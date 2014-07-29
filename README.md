Exrabbit
========

Elixir client for RabbitMQ, based on [rabbitmq-erlang-client][1].

  [1]: https://github.com/rabbitmq/rabbitmq-erlang-client


## Rationale

This project's aim is not to be a complete replacement for the Erlang client.
Instead, it captures common usage patterns and exposes them as a higher level
API.

Climbing the ladder of abstraction even higher, Exrabbit provides a set of DSLs
that make writing common types of AMQP producers and consumers a breeze.


## Installation

Add Exrabbit as a dependency to your project:

```elixir
def application do
  [applications: [:exrabbit]]
end

def deps do
  [{:exrabbit, github: "inbetgames/exrabbit"}]
end
```


## Configuration

Exrabbit can be configured using `config.exs` (see the bundled one for the
available settings) or YAML (via [Sweetconfig][2]).

  [2]: https://github.com/inbetgames/sweetconfig

Example `config.exs`:

```elixir
use Mix.Config

config :exrabbit,
  host: "localhost",
  username: "guest",
  password: "guest",
  confirm_timeout: 5000
```


## Preliminaries

In all examples below we will assume the following aliases have been defined:

```elixir
alias Exrabbit.Producer
alias Exrabbit.Consumer

# this call is needed when working with records
require Exrabbit.Records
```

### Aside: working with records

In order to provide the complete functionality implemented by the Erlang
client, in some cases Exrabbit relies on Erlang records that represent AMQP
methods. A single method is an instance of a record and it is executed on a
channel.

See `doc/records.md` for an overview of which records have been inherited from
the Erlang client and which ones have been superceded by a higher level API.


## Usage (DSL)

It is often desirable for the consumer to be a GenServer. For this reason
Exrabbit provides a DSL that simplifies the task of building one.

First, we set up a producer with a fanout exchange.

```elixir
exchange = exchange_declare(exchange: "test_fanout_x", type: "fanout")
producer = Producer.new(exchange: exchange)
```

Next, we need a consumer module.

```elixir
defmodule TestConsumer do
  # specify the name of our exchange and create a new exclusive queue
  use Exrabbit.Consumer.DSL, exchange: "test_fanout_x", new_queue: ""

  alias Exrabbit.Message

  require Lager

  def init(state) do
    {:ok, state}
  end

  on nil do
    nil -> Lager.info "Got nil message"
  end

  on %Message{delivery_tag: tag, message: body}, state do
    Lager.info "Got message with tag #{tag} and payload #{body}"
    ack(tag)
    {:noreply, state}
  end
end
```

After spawning a consumer process (either manually or with the help of a
supervisor) we can start publishing messages and receiving them on the consumer
end.

```elixir
import Supervisor.Spec, warn: false

# Create multiple workers, customizing the behaviour of each one by passing
# different arguments.
children = [
  worker(TestConsumer, []),
  worker(TestConsumer, []),
  worker(TestConsumer, []),
]

opts = [strategy: :one_for_one, name: Exrabbit.Supervisor]
Supervisor.start_link(children, opts)

# Back on the producer end.
Producer.publish(producer, "[info] just a log message")
Producer.publish(producer, "[info] it's being broadcasted")
Producer.publish(producer, "[error] something unxpected happened")

# Once we're done with the producer, we can shut it down.
# The consumers can be shut down via Supervisor.terminate_child.
Producer.shutdown(producer)
```

## Usage (basic)

### Publishing to a queue

A basic example of a publisher:

```elixir
# Open a connection and a channel, then create a producer on the channel.
# Producer is just a struct encapsulating the connection, the exchange (default
# one in this case) and the queue.
producer = Producer.new(queue: "hello_queue")
Producer.publish(producer, "message")
Producer.publish(producer, "bye-bye")

# Close the channel and connection in one go.
Producer.shutdown(producer)
```

One can also feed a stream of binaries into a producer:

```elixir
Producer.new(queue: "hello_queue")
Enum.into(IO.binstream(:stdio, :line), producer)
Producer.shutdown(producer)
```

To adjust properties of a queue, one can use a record for the queue:

```elixir
# We are using a record provided by the Erlang client here.
queue = Exrabbit.Records.queue_declare(queue: "name", auto_delete: true, exclusive: false)

producer = Producer.new(queue: queue)
Producer.publish(producer, "message")
Producer.shutdown(producer)
```

### Publishing to an exchange

Most of the time you'll be working with exchanges because they provide a more
flexible way to route messages to different queues and eventually consumers.

```elixir
alias Exrabbit.Connection

# To have more than one producer operate on the same channel, we can open it
# upfront.
conn = %Connection{chan: chan} = Connection.open()

# Again, using a record from the Erlang client.
exchange = Exrabbit.Records.exchange_declare(exchange: "logs", type: "fanout")
fanout = Producer.new(chan: chan, exchange: exchange)

Producer.publish(fanout, "[info] some log")
Producer.publish(fanout, "[error] crashed")


exchange = Exrabbit.Records.exchange_declare(exchange: "more_logs", type: "topic")
topical = Producer.new(chan: chan, exchange: exchange)

Producer.publish(topical, "some log", routing_key: "logs.info")
Producer.publish(topical, "crashed", routing_key: "logs.error")

Connection.close(conn)
```

### Receiving messages

When receiving messages, the client sets up a queue, binds it to an exchange
and subscribes to the queue to be notified of incoming messages:

```elixir
topical_exchange = Exrabbit.Records.exchange_declare(exchange: "more_logs", type: "topic")

subscription_fun = fn
  {:begin, _tag} -> IO.puts "Did subscribe"
  {:end, _tag} -> IO.puts "Subscription ended"
  {:msg, _tag, message} -> IO.puts "Received message from queue: #{message}"
end

# Bind a new exclusive queue to the exchange and subscribe to it.
consumer =
  Consumer.new(exchange: topical_exchange, new_queue: "")
  |> Consumer.subscribe(subscription_fun)

# Arriving messages will be consumed by subscription_fun.
# ...

Consumer.unsubscribe(consumer)
Consumer.shutdown(consumer)
```

There is also a way to request messages one by one using the `get` function:

```elixir
consumer = Consumer.new(exchange: topical_exchange, queue: queue)
{:ok, message} = Consumer.get(consumer)
nil = Consumer.get(consumer)
Consumer.shutdown(consumer)
```

### Producer confirms and transactions

An open channel can be switched to confirm-mode or tx-mode.

In confirm mode each published message will be ack'ed or nack'ed by the broker.

In tx-mode one has to call `Exrabbit.Producer.commit` after sending a batch of
messages. Those messages will be delivered atomically: either all or nothing.

See `doc/producer_basic.md` for examples.

### Consumer acknowledgements

When receiving messages, consumers may specify whether the broker should wait
for acknowledgement before removing a message from the queue.

See `doc/consumer_basic.md` for examples.


## OLD README ##

Easy way to get a queue/exchange worker:


```elixir
import Exrabbit.DSL

amqp_worker TestQ, queue: "testQ" do
  on json = %{} do
    IO.puts "JSON: #{inspect json}"
  end
  on <<"hello">> do
    IO.puts "Hello-hello from MQ"
  end
  on text do
    IO.puts "Some random binary: #{inspect text}"
  end
end
```

N.B. Instead of passing configuration options when defining module with `amqp_worker` one can add following to config.exs:

```elixir
[
  exrabbit: [
    my_queue: [queue: "TestQ"]
  ]
]
```

and then define module as:


```elixir
amqp_worker TestQ, config_name: :my_queue, decode_json: [keys: :atoms] do
  on %{cmd: "resize_image", image: image} do
    IO.puts "Resizing image: #{inspect image}"
  end
end
```


Checking if message was published:


```elixir
publish(channel, exchange, routing_key, message, :wait_confirmation)
```


Workflow to send message:


```elixir
amqp = Exrabbit.Utils.connect
channel = Exrabbit.Utils.channel amqp
Exrabbit.Utils.publish channel, "testExchange", "", "hello, world"
```


To get messages, almost the same, but functions are


```elixir
Exrabbit.Utils.get_messages channel, "testQueue"
case Exrabbit.Utils.get_messages_ack channel, "testQueue" do
	nil -> IO.puts "No messages waiting"
	[tag: tag, content: message] ->
		IO.puts "Got message #{message}"
		Exrabbit.Utils.ack tag # acking message
end
```


Please consult: http://www.rabbitmq.com/erlang-client-user-guide.html#returns to find out how to write gen_server consuming messages.


```elixir
defmodule Consumer do
  use GenServer.Behaviour
  import Exrabbit.Utils
  require Lager

  def start_link, do: :gen_server.start_link(Consumer, [], [])

  def init(_opts) do
    amqp = connect
    channel = channel amqp
    subscribe channel, "testQ"
    {:ok, [connection: amqp, channel: channel]}
  end

  def handle_info(request, state) do
    case parse_message(request) do
      nil -> Lager.info "Got nil message"
      {tag, payload} ->
        Lager.info "Got message with tag #{tag} and payload #{payload}"
        ack state[:channel], tag
    end
    { :noreply, state}
  end
end
```


Or same, using behaviours:


```elixir
defmodule Test do
  use Exrabbit.Subscriber

  def handle_message(msg, _state) do
    case parse_message(msg) do
      nil ->
        IO.puts "Nil"
      {tag,json} ->
        IO.puts "Msg: #{json}"
        ack _state[:channel], tag
      {tag,json,reply_to} ->
        IO.puts "For RPC messaging: #{json}"
        publish(_state[:channel], "", reply_to, "#{json}") # Return ECHO
        ack _state[:channel], tag
    end
  end
end

:gen_server.start Test, [queue: "testQ"], []
```




