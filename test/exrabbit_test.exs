defmodule ExrabbitTest do
  use ExUnit.Case

  # You need to have a RabbitMQ server running on localhost

  @test_queue_name "exrabbit_test"
  @test_payload "Hello тест ありがとう＾ー＾"

  test "basic send receive" do
    alias Exrabbit.Connection, as: Conn
    use Exrabbit.Defs

    msg_count = 3

    parent = self()
    subfun = fn
      :start -> send(parent, {self(), :amqp_started})
      :end -> send(parent, {self(), :amqp_finished})
      {:msg, message} -> send(parent, {self(), :amqp_received, message})
    end
    queue = queue_declare(queue: @test_queue_name, auto_delete: true)

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer = %Exrabbit.Consumer{pid: pid} =
      Exrabbit.Consumer.new(recv_chan, queue: queue, subscribe: subfun)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    # send
    conn = %Conn{channel: chan} = Conn.open()
    producer = Exrabbit.Producer.new(chan, queue: queue)
    Enum.each(1..msg_count, fn _ ->
      Exrabbit.Producer.publish(producer, @test_payload)
    end)
    :ok = Conn.close(conn)

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    Exrabbit.Consumer.unsubscribe(consumer)
    assert_receive {^pid, :amqp_finished}
    refute_receive _
    refute Process.alive?(pid)

    :ok = Conn.close(recv_conn)
  end

  test "fanout exchange" do
    alias Exrabbit.Connection, as: Conn
    use Exrabbit.Defs

    msg_count = 3

    parent = self()
    pid = spawn_link(fn ->
      receive do
        Exrabbit.Defs.basic_consume_ok() ->
          send(parent, {self(), :amqp_started})
      end
      Enum.each(1..msg_count, fn _ ->
        receive do
          {Exrabbit.Defs.basic_deliver(), Exrabbit.Defs.amqp_msg(payload: body)} ->
            send(parent, {self(), :amqp_received, body})
        end
      end)
    end)

    exchange = exchange_declare(exchange: "fanout_test", type: "fanout")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    Exrabbit.Consumer.new(recv_chan, exchange: exchange, new_queue: "", subscribe: pid)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    # send
    conn = %Conn{channel: chan} = Conn.open()
    producer = Exrabbit.Producer.new(chan, exchange: "fanout_test")
    Enum.each(1..msg_count, fn _ ->
      Exrabbit.Producer.publish(producer, @test_payload)
    end)
    :ok = Conn.close(conn)

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    :ok = Conn.close(recv_conn)
  end

  test "fanout exchange stream" do
    alias Exrabbit.Connection, as: Conn
    use Exrabbit.Defs

    parent = self()
    subfun = fn
      :start -> send(parent, {self(), :amqp_started})
      :end -> send(parent, {self(), :amqp_finished})
      {:msg, message} -> send(parent, {self(), :amqp_received, message})
    end

    exchange = exchange_declare(exchange: "fanout_stream_test", type: "fanout")

    # receive
    recv_conn = %Conn{channel: recv_chan} = Conn.open()
    consumer = %Exrabbit.Consumer{pid: pid} =
      Exrabbit.Consumer.new(recv_chan, exchange: exchange, new_queue: "", subscribe: subfun)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    # send
    conn = %Conn{channel: chan} = Conn.open()
    producer = Exrabbit.Producer.new(chan, exchange: "fanout_stream_test")
    Enum.into(["hello", "it's", "me"], producer)
    :ok = Conn.close(conn)

    assert_receive {^pid, :amqp_received, "hello"}
    assert_receive {^pid, :amqp_received, "it's"}
    assert_receive {^pid, :amqp_received, "me"}
    refute_receive _

    Exrabbit.Consumer.unsubscribe(consumer)
    assert_receive {^pid, :amqp_finished}
    refute_receive _
    refute Process.alive?(pid)

    :ok = Conn.close(recv_conn)
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
