defmodule ExrabbitTest do
  use ExUnit.Case

  # You need to have a RabbitMQ server running on localhost

  @test_queue_name "exrabbit_test"
  @test_payload "Hello тест ありがとう＾ー＾"

  test "basic send receive" do
    import Exrabbit.Utils
    require Exrabbit.Defs

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

    # receive
    recv_conn = connect()
    recv_chan = channel_open(recv_conn)
    declare_queue(recv_chan, @test_queue_name, true)
    subscribe(recv_chan, @test_queue_name, pid)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    # send
    conn = connect()
    chan = channel_open(conn)
    declare_queue(chan, @test_queue_name, true)
    Enum.each(1..msg_count, fn _ ->
      publish(chan, "", @test_queue_name, @test_payload)
    end)
    :ok = channel_close(chan)
    :ok = disconnect(conn)

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    :ok = channel_close(recv_chan)
    :ok = disconnect(recv_conn)
  end
end
