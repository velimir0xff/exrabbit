defmodule ExrabbitTest.BasicTest do
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
    consumer = %Consumer{pid: pid} =
      Consumer.new(queue: queue)
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

    :ok = Consumer.shutdown(consumer)
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
    consumer =
      Consumer.new(exchange: exchange, new_queue: "")
      |> Consumer.subscribe(pid)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    produce([exchange: "fanout_test"], Enum.map(1..msg_count, fn _ -> @test_payload end))

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    :ok = Consumer.shutdown(consumer)
  end

  test "fanout exchange stream" do
    exchange = exchange_declare(exchange: "fanout_stream_test", type: "fanout")

    # receive
    consumer = %Consumer{pid: pid} =
      Consumer.new(exchange: exchange, new_queue: "")
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

    :ok = Consumer.shutdown(consumer)
  end

  test "multiple subscribers per process" do
    exchange = exchange_declare(exchange: "fanout_stream_test", type: "fanout")

    # receive
    conn = %Conn{chan: chan} = Conn.open()
    consumer1 = %Consumer{pid: pid1, tag: tag1} =
      Consumer.new(chan: chan, exchange: exchange, new_queue: "")
      |> Consumer.subscribe(subfun(self()))

    consumer2 = %Consumer{pid: pid2, tag: tag2} =
      Consumer.new(chan: chan, exchange: exchange, new_queue: "")
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

    :ok = Conn.close(conn)
  end

  test "get message" do
    exchange = exchange_declare(exchange: "direct_test", type: "direct")

    # receive
    conn = %Conn{chan: chan} = Conn.open()
    consumer_black =
      Consumer.new(chan: chan, exchange: exchange, new_queue: "", binding_key: "black")
    consumer_red =
      Consumer.new(chan: chan, exchange: exchange, new_queue: "", binding_key: "red")

    produce([exchange: "direct_test"], fn producer ->
      Producer.publish(producer, "night", routing_key: "black")
      Producer.publish(producer, "sun", routing_key: "red")
      Producer.publish(producer, "ash", routing_key: "black")
    end)

    assert {:ok, "night"} = Consumer.get_body(consumer_black)
    assert {:ok, "sun"} = Consumer.get_body(consumer_red)
    assert nil = Consumer.get_body(consumer_red)

    assert {:ok, %Message{
        exchange: "direct_test",
        routing_key: "black",
        message: "ash"}
    } = Consumer.get(consumer_black)

    :ok = Conn.close(conn)
  end

  test "get with ack" do
    queue = queue_declare(queue: "test_ack_queue", auto_delete: true)

    # receive
    consumer = Consumer.new(queue: queue)

    produce([queue: queue], ["night", "ash"])

    assert {:ok, "night"} = Consumer.get_body(consumer)

    assert {:ok, %Message{
        routing_key: "test_ack_queue",
        message: "ash"}=msg
    } = Consumer.get(consumer, no_ack: false)
    assert nil = Consumer.get(consumer)
    assert :ok = Consumer.nack(consumer, msg)

    assert {:ok, %Message{
        routing_key: "test_ack_queue",
        message: "ash"}=msg
    } = Consumer.get(consumer, no_ack: false)
    assert :ok = Consumer.ack(consumer, msg)
    assert nil = Consumer.get(consumer)

    :ok = Consumer.shutdown(consumer)
  end

  test "publish with confirm" do
    queue = queue_declare(queue: "confirm_test", auto_delete: true)

    # receive
    consumer = Consumer.new(queue: queue)

    # send
    producer = %Producer{chan: pchan} = Producer.new(queue: "confirm_test")
    assert :not_in_confirm_mode = catch_throw(
      Producer.publish(producer, "hi", await_confirm: true, timeout: 100)
    )
    # the message could have been published or not; we don't know for sure
    assert Exrabbit.Channel.queue_purge(pchan, "confirm_test") in [0, 1]

    Exrabbit.Channel.set_mode(pchan, :confirm)
    assert :ok = Producer.publish(producer, "hi", await_confirm: true, timeout: 100)
    assert :ok = Producer.publish(producer, "1")
    assert :ok = Producer.publish(producer, "2")
    assert :ok = Producer.publish(producer, "3")
    assert :ok = Exrabbit.Channel.await_confirms(pchan, 100)

    :ok = Producer.shutdown(producer)
    # end send

    assert {:ok, "hi"} = Consumer.get_body(consumer)
    assert {:ok, "1"} = Consumer.get_body(consumer)
    assert {:ok, "2"} = Consumer.get_body(consumer)
    assert {:ok, "3"} = Consumer.get_body(consumer)

    :ok = Consumer.shutdown(consumer)
  end

  test "delete queue in use" do
    queue = queue_declare(queue: "delete_queue_test", auto_delete: true)

    producer = Producer.new(queue: queue)
    Producer.publish(producer, "hello")

    %Consumer{chan: chan} = Consumer.new(queue: queue)
    #assert 0 = Exrabbit.Channel.queue_delete(chan, "delete_queue_test", if_unused: true)
    assert {{:shutdown, {_, _, "PRECONDITION_FAILED" <> _}}, _} =
      catch_exit(Exrabbit.Channel.queue_delete(chan, "delete_queue_test", if_empty: true))
    # no consumer shutdown needed

    Producer.shutdown(producer)
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
    producer = Producer.new([{:exchange, exchange}, queue])
    fun.(producer)
    :ok = Producer.shutdown(producer)
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
