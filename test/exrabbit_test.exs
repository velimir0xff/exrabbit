defmodule ExrabbitTest do
  use ExUnit.Case

  # You need to have a RabbitMQ server running on localhost

  @test_queue_name "exrabbit_test"
  @test_payload "Hello тест ありがとう＾ー＾"

  alias Exrabbit.Connection, as: Conn
  alias Exrabbit.Producer
  alias Exrabbit.Consumer
  alias Exrabbit.Message
  use Exrabbit.Records

  test "basic send receive" do
    queue = queue_declare(queue: @test_queue_name, auto_delete: true)

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer = %Consumer{pid: pid} =
      Consumer.new(recv_chan, queue: queue)
      |> Consumer.subscribe(subfun(self()))

    assert_receive {^pid, :amqp_started, _}
    refute_receive _

    msg_count = 3
    produce([queue: queue], Enum.map(1..msg_count, fn _ -> @test_payload end))

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, _, @test_payload}
    end)
    refute_receive _

    Consumer.unsubscribe(consumer)
    assert_receive {^pid, :amqp_finished, _}
    refute_receive _
    refute Process.alive?(pid)

    :ok = Conn.close(recv_conn)
  end

  test "fanout exchange" do
    msg_count = 4

    parent = self()
    pid = spawn_link(fn ->
      receive do
        basic_consume_ok() ->
          send(parent, {self(), :amqp_started})
      end
      Enum.each(1..msg_count, fn _ ->
        receive do
          {basic_deliver(), amqp_msg(payload: body)} ->
            send(parent, {self(), :amqp_received, body})
        end
      end)
    end)

    exchange = exchange_declare(exchange: "fanout_test", type: "fanout")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    Consumer.new(recv_chan, exchange: exchange, new_queue: "")
    |> Consumer.subscribe(pid)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    produce([exchange: "fanout_test"], Enum.map(1..msg_count, fn _ -> @test_payload end))

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    :ok = Conn.close(recv_conn)
  end

  test "fanout exchange stream" do
    exchange = exchange_declare(exchange: "fanout_stream_test", type: "fanout")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer = %Consumer{pid: pid} =
      Consumer.new(recv_chan, exchange: exchange, new_queue: "")
      |> Consumer.subscribe(subfun(self()))

    assert_receive {^pid, :amqp_started, _}
    refute_receive _

    produce([exchange: "fanout_stream_test"], fn producer ->
      Enum.into(["hello", "it's", "me"], producer)
    end)

    assert_receive {^pid, :amqp_received, _, "hello"}
    assert_receive {^pid, :amqp_received, _, "it's"}
    assert_receive {^pid, :amqp_received, _, "me"}
    refute_receive _

    Consumer.unsubscribe(consumer)
    assert_receive {^pid, :amqp_finished, _}
    refute_receive _
    refute Process.alive?(pid)

    :ok = Conn.close(recv_conn)
  end

  test "multiple subscribers per process" do
    exchange = exchange_declare(exchange: "fanout_stream_test", type: "fanout")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer1 = %Consumer{pid: pid1, tag: tag1} =
      Consumer.new(recv_chan, exchange: exchange, new_queue: "")
      |> Consumer.subscribe(subfun(self()))

    consumer2 = %Consumer{pid: pid2, tag: tag2} =
      Consumer.new(recv_chan, exchange: exchange, new_queue: "")
      |> Consumer.subscribe(subfun(self()))

    assert_receive {^pid1, :amqp_started, ^tag1}
    assert_receive {^pid2, :amqp_started, ^tag2}
    refute_receive _

    produce([exchange: "fanout_stream_test"], fn producer ->
      Enum.into(["hello", "it's", "me"], producer)
    end)

    Enum.each([{pid1, tag1}, {pid2, tag2}], fn {pid, tag} ->
      assert_receive {^pid, :amqp_received, ^tag, "hello"}
      assert_receive {^pid, :amqp_received, ^tag, "it's"}
      assert_receive {^pid, :amqp_received, ^tag, "me"}
    end)
    refute_receive _

    Consumer.unsubscribe(consumer1)
    assert_receive {^pid1, :amqp_finished, ^tag1}
    refute_receive _
    Consumer.unsubscribe(consumer2)
    assert_receive {^pid2, :amqp_finished, ^tag2}
    refute_receive _

    :ok = Conn.close(recv_conn)
  end

  test "get message" do
    exchange = exchange_declare(exchange: "direct_test", type: "direct")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer_black =
      Consumer.new(recv_chan, exchange: exchange, new_queue: "", binding_key: "black")
    consumer_red =
      Consumer.new(recv_chan, exchange: exchange, new_queue: "", binding_key: "red")

    produce([exchange: "direct_test"], fn producer ->
      Producer.publish(producer, "night", routing_key: "black")
      Producer.publish(producer, "sun", routing_key: "red")
      Producer.publish(producer, "ash", routing_key: "black")
    end)

    assert {:ok, "night"} = Consumer.get(consumer_black)
    assert {:ok, "sun"} = Consumer.get(consumer_red)
    assert {:error, :empty_response} = Consumer.get(consumer_red)

    assert {:ok, %Message{
        exchange: "direct_test",
        routing_key: "black",
        message: amqp_msg(payload: "ash")}
    } = Consumer.get_full(consumer_black)

    :ok = Conn.close(recv_conn)
  end

  test "get with ack" do
  end

  test "publish with confirm" do
    queue = queue_declare(queue: "confirm_test", auto_delete: true)

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer = Consumer.new(recv_chan, queue: queue)

    # send
    conn = %Conn{channel: chan} = Conn.open()
    producer = Producer.new(chan, queue: "confirm_test")
    assert :not_in_confirm_mode = catch_throw(
      Producer.publish(producer, "hi", await_confirm: true, timeout: 100)
    )
    # the message could have been published or not; we don't know for sure
    purge = queue_purge(queue: "confirm_test")
    queue_purge_ok() = :amqp_channel.call(chan, purge)

    Exrabbit.Channel.set_mode(chan, :confirm)
    assert :ok = Producer.publish(producer, "hi", await_confirm: true, timeout: 100)
    assert :ok = Producer.publish(producer, "1")
    assert :ok = Producer.publish(producer, "2")
    assert :ok = Producer.publish(producer, "3")
    assert :ok = Exrabbit.Channel.await_confirms(chan, 100)

    :ok = Conn.close(conn)
    # end send

    assert {:ok, "hi"} = Consumer.get(consumer)
    assert {:ok, "1"} = Consumer.get(consumer)
    assert {:ok, "2"} = Consumer.get(consumer)
    assert {:ok, "3"} = Consumer.get(consumer)

    :ok = Conn.close(recv_conn)
  end

  ###

  defp produce(opts, fun) when is_function(fun) do
    do_produce(opts, fun)
  end

  defp produce(opts, messages) when is_list(messages) do
    do_produce(opts, fn producer ->
      Enum.each(messages, fn message ->
        Producer.publish(producer, message)
      end)
    end)
  end

  defp subfun(pid) do
    fn
      {:begin, tag} -> send(pid, {self(), :amqp_started, tag})
      {:end, tag} -> send(pid, {self(), :amqp_finished, tag})
      {:msg, tag, message} -> send(pid, {self(), :amqp_received, tag, message})
    end
  end

  defp do_produce(opts, fun) do
    exchange = Keyword.get(opts, :exchange, "")
    queue = case {Keyword.get(opts, :queue, nil), Keyword.get(opts, :new_queue, nil)} do
      {nil, name} -> {:new_queue, name}
      {queue, nil} -> {:queue, queue}
    end

    # send
    conn = %Conn{channel: chan} = Conn.open()
    producer = Producer.new(chan, [{:exchange, exchange}, queue])
    fun.(producer)
    :ok = Conn.close(conn)
  end

  #  test "low-level send receive" do
  #    alias Exrabbit.Channel, as: Chan
  #    use Exrabbit.Defs
  #
  #    # send
  #    conn = {chan, _} = Chan.open()
  #
  #    exchange_rm = exchange_delete(exchange: "test_exchange")
  #    exchange = exchange_declare(exchange: "test_exchange", type: "direct", durable: true)
  #    Chan.exec(chan, [exchange_rm, exchange])
  #
  #    # receive
  #    recv_conn = {recv_chan, _} = Chan.open()
  #
  #    queue1 = queue_declare(queue: "queue_black", auto_delete: true)
  #    bind1 = queue_bind(exchange: "test_exchange", routing_key: "black")
  #    queue2 = queue_declare(queue: "queue_red", auto_delete: true)
  #    bind2 = queue_bind(exchange: "test_exchange", routing_key: "red")
  #    Chan.exec(recv_chan, [exchange, queue1, bind1, queue2, bind2])
  #
  #    # send
  #    Chan.publish(chan, "test_exchange", "black", "hello black exchange!")
  #    Chan.publish(chan, "test_exchange", "red", "hello red exchange!")
  #
  #    :ok = Chan.close(conn)
  #
  #    # receive
  #    assert "hello black exchange!" = Chan.get_messages(recv_chan, "queue_black")
  #    assert "hello red exchange!" = Chan.get_messages(recv_chan, "queue_red")
  #
  #    :ok = Chan.close(recv_conn)
  #  end
end
