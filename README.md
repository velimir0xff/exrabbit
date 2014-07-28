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

Configure it using `config.exs` (see the bundled one for the available
settings) or YAML (via [Sweetconfig][2]).

  [2]: https://github.com/inbetgames/sweetconfig


## Usage (DSL)


## Usage (basic)

In all of the example below we will assume the following aliases have been
defined:

```elixir
alias Exrabbit.Connection, as: Conn
alias Exrabbit.Channel, as: Chan
alias Exrabbit.Producer, as: Producer
alias Exrabbit.Consumer, as: Consumer

# this call is needed when working with records
require Exrabbit.Records
```

### Publishing to a queue

A basic example of a publisher:

```elixir
# Open both a connection to the broker and a channel in one go
conn = %Conn{channel: chan} = Conn.open(with_channel: true)

# Create a producer on the chan
# producer is just a struct encapsulating the exchange (default one in this case)
# and the queue
producer = Producer.new(chan, queue: "hello_queue")
Producer.publish(producer, "message")
Producer.publish(producer, "bye-bye")

# Close the channel and connection in one go
Conn.close(conn)
```

One can also feed a stream of binaries into a producer:

```elixir
# Create a producer on the chan
stream = IO.binstream(:stdio, :line)
producer = Producer.new(chan, queue: "hello_queue")
Enum.into(producer, stream)
```

To adjust properties of a queue, one can use a record for the queue:

```elixir
conn = %Conn{channel: chan} = Conn.open(with_channel: true)

# we are using a record provided by the Erlang client here
queue = Exrabbit.Records.queue_declare(queue: "name", auto_delete: true, exclusive: false)
producer = Producer.new(chan, queue: queue)
Producer.publish(producer, "message")
```

### Aside: working with records

In order to provide all of functionality implemented by the Erlang client,
Exrabbit relies on Erlang records that represent AMQP methods. A single method
is an instance of a record and it is normally executed on a channel.

**TODO**: more content

### Publishing to an exchange

Most of the time you'll be working with exchanges because they provide a more
flexible way to route messages to different queues and eventually consumers.

```elixir
# :with_channel is true by default
conn = %Conn{channel: chan} = Conn.open()

# again, using a record from the Erlang client
exchange = Exrabbit.Records.exchange_declare(exchange: "logs", type: "fanout")
fanout = Producer.new(chan, exchange: exchange)

Producer.publish(fanout, "[info] some log")
Producer.publish(fanout, "[error] crashed")


exchange = Exrabbit.Records.exchange_declare(exchange: "more_logs", type: "topic")
topical = Producer.new(chan, exchange: exchange)

Producer.publish(topical, "some log", routing_key: "logs.info")
Producer.publish(topical, "crashed", routing_key: "logs.error")

Conn.close(conn)
```

Side note: messages can be published in a more canonical way using
`Chan.publish`. However, you are encouraged to use `Exrabbit.Producer`.

```elixir
conn = %Conn{channel: chan} = Conn.open(with_channel: true)

exchange = Exrabbit.Records.exchange_declare(exchange: "more_logs", type: "topic")
Chan.publish(chan, "message", exchange: exchange, routing_key: "logs.info")
```

### Receiving messages

When receiving messages, the client sets up a queue, binds it to an exchange
and subscribes to the queue to be notified of incoming messages:

```elixir
conn = %Conn{channel: chan} = Conn.open(with_channel: true)

topical_exchange = Exrabbit.Records.exchange_declare(exchange: "more_logs", type: "topic")

# using a function for subscribtion let's use interact with the simple consumer
# API (as opposed to the complete one)
subscription_fun = fn
  {:begin, _tag} -> IO.puts "Did subscribe"
  {:end, _tag} -> IO.puts "Subscription ended"
  {:msg, _tag, message} -> IO.puts "Received message from queue: #{message}"
end

# bind the queue to the exchange and subscribe to it
consumer =
  Consumer.new(chan, exchange: topical_exchange, new_queue: "")
  |> Consumer.subscribe(subscription_fun)

# arriving messages will be consumed by subscription_fun
# ...

Consumer.unsubscribe(consumer)

Conn.close(conn)
```

There is also a way to request messages one by one using the `get` function:

```elixir
# assume we have set up the channel as before

consumer = Consumer.new(chan, exchange: topical_exchange, queue: queue)

{:ok, message} = Consumer.get(consumer, no_ack: true)
```


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




