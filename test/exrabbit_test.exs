defmodule ExrabbitTest do
  use ExUnit.Case

  # You need to have a RabbitMQ server running on localhost

  @test_queue_name "exrabbit_test"
  @test_payload "Hello тест ありがとう＾ー＾"

  test "basic send receive" do
    alias Exrabbit.Channel, as: Chan
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

    queue = queue_declare(queue: @test_queue_name, auto_delete: true)

    # receive
    recv_conn = {recv_chan, _} = Chan.open()
    Chan.declare_queue(recv_chan, queue)
    Chan.subscribe(recv_chan, @test_queue_name, pid)

    assert_receive {^pid, :amqp_started}
    refute_receive _

    # send
    conn = {chan, _} = Chan.open()
    Chan.declare_queue(chan, queue)
    Enum.each(1..msg_count, fn _ ->
      Chan.publish(chan, "", @test_queue_name, @test_payload)
    end)
    :ok = Chan.close(conn)

    Enum.each(1..msg_count, fn _ ->
      assert_receive {^pid, :amqp_received, @test_payload}
    end)
    refute_receive _

    :ok = Chan.close(recv_conn)
  end
end
