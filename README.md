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

The current version is based on rabbitmq-erlang-client v3.3.0 (AMQP 0-9-1 with
extensions).


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

In order to provide the complete functionality implemented by the Erlang
client, in some cases Exrabbit relies on Erlang records that represent AMQP
methods. A single method is an instance of a record and it is executed on a
channel.

See `doc/records.md` for an overview of which records have been inherited from
the Erlang client and which ones are superceded by a higher level API.

In all examples below we will assume the following aliases have been defined:

```elixir
alias Exrabbit.Producer
alias Exrabbit.Consumer

# this call is needed when working with records
require Exrabbit.Records
```


## Usage (DSL)

It is often desirable for the consumer to be a GenServer. For this reason
Exrabbit provides a DSL that simplifies the task of building one.

First, we set up a producer with a topic exchange.

```elixir
exchange = exchange_declare(exchange: "test_topic_x", type: "topic")
producer = Producer.new(exchange: exchange)
```

Next, we need a consumer module.

```elixir
defmodule TestConsumer do
  use Exrabbit.Consumer.DSL,
    exchange: "test_topic_x", new_queue: "", no_ack: false

  require Lager

  init [log_level] do
    # Specifying options as the last element in the return tuple will override
    # corresponding options passed to he `use` call above.
    {:ok, log_level, binding_key: log_level}
  end

  on %Message{message: body}=msg, level, consumer do
    log(level, "#{inspect self()}: Got message with tag #{tag} and payload #{body}")
    {:ack, level}
  end

  defp log("info", msg) do
    Lager.info(msg)
  end

  defp log("debug", msg) do
    Lager.debug(msg)
  end

  defp log("error", msg) do
    Lager.error(msg)
  end
end
```

After spawning a consumer process (either manually or with the help of a
supervisor) we can start publishing messages and receiving them on the consumer
end.

```elixir
import Supervisor.Spec

# Create multiple workers, customizing the behaviour of each one by passing
# different arguments.
children = [
  worker(TestConsumer, ["info"]),
  worker(TestConsumer, ["debug"]),
  worker(TestConsumer, ["error"]),
]

opts = [strategy: :one_for_one, name: Exrabbit.Supervisor]
Supervisor.start_link(children, opts)


# Back on the producer end.
Producer.publish(producer, "just a log message", routing_key: "info")
Producer.publish(producer, "it's being broadcasted", routing_key: "debug")
Producer.publish(producer, "to all who are interested", routing_key: "error")

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

See `doc/basic_producer.md` for examples.

### Consumer acknowledgements

When receiving messages, consumers may specify whether the broker should wait
for acknowledgement before removing a message from the queue.

See `doc/basic_consumer.md` for examples.


## Further information

If you find any parts for the documentation lacking, please report an issues on
the tracker. In the meantime, you may consult the documentation for the [Erlang
client][erldoc] and this [quick reference][refdoc] that describes AMQP methods
in detail.

All check out the detailed guide for the Ruby client [here][rubydoc], most of
which applies to Exrabbit as well.

  [refdoc]: http://www.rabbitmq.com/amqp-0-9-1-reference.html
  [erldoc]: http://www.rabbitmq.com/releases/rabbitmq-erlang-client/v3.3.4/doc/
  [rubydoc]: http://rubybunny.info/articles/guides.html


## License

This software is licensed under [the MIT license](LICENSE).
