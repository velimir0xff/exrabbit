defmodule TestConsumer do
  use Exrabbit.Consumer.DSL,
    exchange: exchange_declare(exchange: "test_topic_x", type: "topic"),
    new_queue: ""

  use GenServer

  def start_link(name, key) do
    GenServer.start_link(__MODULE__, [name, key])
  end

  init [name, key] do
    {:ok, name, binding_key: key}
  end

  on %Message{body: body}, name do
    IO.puts "#{name} received #{body}"
    {:noreply, name}
  end
end

defmodule TestConsumerAppConfig do
  use Exrabbit.Consumer.DSL,
    config_name: :test_consumer_config

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  init [] do
    {:ok, nil}
  end

  on %Message{body: body}, nil, consumer do
    IO.puts "received #{body} (queue: #{consumer.queue})"
    {:noreply, nil}
  end
end

defmodule TestConsumerAck do
  use Exrabbit.Consumer.DSL,
    exchange: exchange_declare(exchange: "test_topic_x", type: "topic"),
    new_queue: "dsl_auto_ack_queue",
    binding_key: "ackinator",
    no_ack: false

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  init [] do
    {:ok, nil}
  end

  on %Message{body: body}, nil do
    IO.puts "received and promised to acknowledge #{body}"
    {:ack, nil}
  end
end

defmodule TestConsumerAckManual do
  use Exrabbit.Consumer.DSL,
    exchange: exchange_declare(exchange: "test_topic_x", type: "topic"),
    new_queue: "dsl_man_ack_queue",
    no_ack: false

  use GenServer

  def start_link(name, key) do
    GenServer.start_link(__MODULE__, [name, key])
  end

  init [name, key] do
    {:ok, name, binding_key: key}
  end

  on %Message{body: "don't ack me"}, name do
    IO.puts "#{name} skipped ack"
    {:noreply, name}
  end

  on %Message{body: body}=msg, name, consumer do
    ack(consumer, msg)
    IO.puts "#{name} received and acknowledged #{body}"
    {:noreply, name}
  end
end

defmodule TestConsumerJson do
  use Exrabbit.Consumer.DSL,
    queue: queue_declare(queue: "test_json_queue"),
    format: :json

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  init [] do
    {:ok, nil}
  end

  on %Message{body: body}, nil, consumer do
    IO.puts "received #{inspect body} (queue: #{consumer.queue})"
    {:noreply, nil}
  end

  on_error reason, nil do
    IO.puts "got decoding error with reason: #{inspect reason}"
    {:noreply, nil}
  end
end

defmodule TestConsumerBinary do
  use Exrabbit.Consumer.DSL,
    queue: queue_declare(queue: "test_bin_queue"),
    format: :binary

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  init [] do
    {:ok, nil}
  end

  on %Message{body: body}, nil, consumer do
    IO.puts "received #{inspect body} (queue: #{consumer.queue})"
    {:noreply, nil}
  end

  on_error reason, nil do
    IO.puts "got decoding error with reason: #{inspect reason}"
    {:noreply, nil}
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

  test "basic dsl with app config" do
    import ExUnit.CaptureIO

    Application.put_env(:exrabbit, :test_consumer_config, %{
      exchange: "test_config_topic_x",
      new_queue: "qqq",
      binding_key: "#",
    })

    expected = """
      received hello (queue: qqq)
      received bye (queue: qqq)
      """

    assert capture_io(fn ->
      use Exrabbit.Records
      exchange = exchange_declare(exchange: "test_config_topic_x", type: "topic")
      producer = Producer.new(exchange: exchange)

      {:ok, consumer} = TestConsumerAppConfig.start_link()

      publish = fn message, key ->
        Producer.publish(producer, message, routing_key: key)
      end
      publish.("hello", "1")
      publish.("bye", "2")
      Producer.shutdown(producer)

      :ok = TestConsumerAppConfig.shutdown(consumer)
    end) == expected
  end

  test "dsl with auto acks" do
    import ExUnit.CaptureIO

    expected = """
      received and promised to acknowledge hello
      received and promised to acknowledge how are you
      """

    assert capture_io(fn ->
      {:ok, consumer} = TestConsumerAck.start_link()

      producer = Producer.new(exchange: "test_topic_x")
      publish = fn message ->
        Producer.publish(producer, message, routing_key: "ackinator")
      end

      publish.("hello")
      publish.("how are you")
      Producer.shutdown(producer)

      #%Consumer{chan: chan} = TestConsumerAck.struct(consumer)
      #assert 0 = Exrabbit.Channel.queue_purge(chan, "dsl_auto_ack_queue")

      :ok = TestConsumer.shutdown(consumer)
    end) == expected
  end

  test "dsl with manual acks" do
    import ExUnit.CaptureIO

    expected = """
      ackinator received and acknowledged hello
      ackinator skipped ack
      ackinator received and acknowledged bye now
      """

    assert capture_io(fn ->
      {:ok, consumer} = TestConsumerAckManual.start_link("ackinator", "-")

      producer = Producer.new(exchange: "test_topic_x")
      publish = fn message, key ->
        Producer.publish(producer, message, routing_key: key)
      end

      publish.("hello", "-")
      publish.("don't ack me", "-")
      publish.("bye now", "-")
      :ok = Producer.shutdown(producer)

      #%Consumer{chan: chan} = TestConsumerAckManual.struct(consumer)
      #assert 1 = Exrabbit.Channel.queue_purge(chan, "dsl_man_ack_queue")

      :ok = TestConsumer.shutdown(consumer)
    end) == expected
  end

  test "dsl with json" do
    import ExUnit.CaptureIO

    expected = ~S"""
      received %{"hello" => "world", "list" => [1, 2, 3]} (queue: test_json_queue)
      got decoding error with reason: {:invalid, "b"}
      received ["a", "b", "c"] (queue: test_json_queue)
      """

    assert capture_io(fn ->
      {:ok, consumer} = TestConsumerJson.start_link()

      producer = Producer.new(queue: "test_json_queue", format: :json)
      Producer.publish(producer, %{"hello" => "world", "list" => [1,2,3]})
      Producer.publish(producer, "bad json", format: nil)
      Producer.publish(producer, ["a", "b", "c"], format: :json)
      Producer.shutdown(producer)

      :ok = TestConsumer.shutdown(consumer)
    end) == expected
  end

  test "dsl with binary" do
    import ExUnit.CaptureIO

    expected = ~S"""
      received %{"hello" => "world", "list" => [1, 2, 3]} (queue: test_bin_queue)
      got decoding error with reason: :badarg
      received ["a", "b", "c"] (queue: test_bin_queue)
      """

    assert capture_io(fn ->
      {:ok, consumer} = TestConsumerBinary.start_link()

      producer = Producer.new(queue: "test_bin_queue", format: :binary)
      Producer.publish(producer, %{"hello" => "world", "list" => [1,2,3]})
      Producer.publish(producer, "bad encoding", format: nil)
      Producer.publish(producer, ["a", "b", "c"])
      Producer.shutdown(producer)

      :ok = TestConsumer.shutdown(consumer)
    end) == expected
  end
end
