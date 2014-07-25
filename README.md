Exrabbit
========

Elixir client for RabbitMQ, based on [rabbitmq-erlang-client][1].

  [1]: https://github.com/rabbitmq/rabbitmq-erlang-client


## Goals and Features

This project doesn't aim to be a swap-in replacement for the Erlang client. It
mostly provides conveniences for common usage patterns. The most prominent
addition on top of the Erlang client is a set of DSLs that make writing common
types of AMQP producers and consumers a breeze.


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

Configure using `config.exs` (see the bundled one for the available settings) or
YAML (via [Sweetconfig][2]).

  [2]: https://github.com/inbetgames/sweetconfig


## Usage (DSL)


## Usage (basic)

**NOTE**: _The instructions below may be outdated due to the ongoing rewrite of the library. Stay tuned for an updated Readme._

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




