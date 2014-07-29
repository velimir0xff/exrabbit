defmodule TestConsumer do
  use Exrabbit.Consumer.DSL,
    exchange: exchange_declare(exchange: "test_topic_x", type: "topic"),
    new_queue: ""

  def start_link(name, key) do
    GenServer.start_link(__MODULE__, [name, key])
  end

  init [name, key] do
    {:ok, name, binding_key: key}
  end

  on %Message{message: body}, name do
    IO.puts "#{name} received #{body}"
    {:noreply, name}
  end
end

defmodule ExrabbitTest.DSLTest do
  use ExUnit.Case

  # You need to have a RabbitMQ server running on localhost

  alias Exrabbit.Producer

  test "basic dsl" do
    import ExUnit.CaptureIO

    expected = """
      orange received hello
      rose received hello to you
      rose received bye-bye
      orange received bye now
      """

    assert capture_io(fn ->
      {:ok, consumer_rose} = TestConsumer.start_link("rose", "1")
      {:ok, consumer_orange} = TestConsumer.start_link("orange", "2")

      producer = %Producer{chan: chan} = Producer.new(exchange: "test_topic_x")
      publish = fn message, key ->
        Producer.publish(producer, message, routing_key: key, await_confirm: true)
      end

      Exrabbit.Channel.set_mode(chan, :confirm)

      publish.("hello", "2")
      publish.("hello to you", "1")
      publish.("bye-bye", "1")
      publish.("bye now", "2")
      Producer.shutdown(producer)

      :ok = TestConsumer.shutdown(consumer_rose)
      :ok = TestConsumer.shutdown(consumer_orange)
    end) == expected
  end
end
