defmodule Exrabbit.Channel do
  use Exrabbit.Defs

  alias Exrabbit.Connection, as: Conn

  @doc """
  Open a new connection with default settings and create a new channel on it.

  Returns `{<chan>, <conn>}` or fails.
  """
  def open() do
    conn = Conn.open()
    chan = open(conn)
    {chan, conn}
  end

  @doc """
  Open a new channel on an established connection.

  Returns a new channel or fails.
  """
  def open(conn) when is_pid(conn) do
    {:ok, chan} = :amqp_connection.open_channel(conn)
    chan
  end

  @doc """
  Close previously opened channel.

  If the argument is a tuple `{<chan>, <conn>}`, closes the connection too.
  """
  def close({chan, conn}) do
    :ok = close(chan)
    Conn.close(conn)
  end

  def close(chan), do: :amqp_channel.close(chan)

  ### Exchange related

  def declare_exchange(chan, exchange) do
    exchange_declare_ok() = :amqp_channel.call(chan, exchange)
    exchange_declare(exchange, :exchange)
  end

  ### Queue related

  @doc """
  Declare an unnamed queue with `:auto_delete` set to `true`.
  """
  def declare_queue(chan) do
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, queue_declare(auto_delete: true))
    name
  end

  @doc """
  Declare a queue using the supplied record.
  """
  def declare_queue(chan, queue) do
    queue_declare_ok(queue: name) = :amqp_channel.call(chan, queue)
    name
  end

  def rpc(channel, exchange, routing_key, message, reply_to) do
    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to), payload: message)
  end

  def rpc(channel, exchange, routing_key, message, reply_to, uuid) do
    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to, headers: ({"uuid", :longstr, uuid})  ), payload: message)
  end


  def publish(channel, exchange, routing_key, message) do
    publish(channel, exchange, routing_key, message, :no_confirmation)
  end

  def publish(channel, exchange, routing_key, message, :no_confirmation) do
    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(payload: message)
  end

  def publish(channel, exchange, routing_key, message, :wait_confirmation) do
    root = self
    confirm_select_ok() = :amqp_channel.call channel, confirm_select()
    :ok = :amqp_channel.register_confirm_handler channel, spawn fn ->
      wait_confirmation(root, channel)
    end
    :ok = publish(channel, exchange, routing_key, message, :no_confirmation)
    receive do
      {:message_confirmed, _data} -> :ok
      {:message_lost, _data} -> {:error, :lost}
      {:confirmation_timeout} -> {:error, :timeout}
    end
  end

  def ack(channel, tag) do
    :amqp_channel.call channel, basic_ack(delivery_tag: tag)
  end
  def nack(channel, tag) do
    :amqp_channel.call channel, basic_nack(delivery_tag: tag)
  end

  def get_messages_ack(channel, queue), do: get_messages(channel, queue, false)
  def get_messages(channel, queue), do: get_messages(channel, queue, true)
  def get_messages(channel, queue, true) do
    case :amqp_channel.call channel, basic_get(queue: queue, no_ack: true) do
      {basic_get_ok(), content} -> get_payload(content)
      basic_get_empty() -> nil
    end
  end

  def get_messages(channel, queue, false) do
    case :amqp_channel.call channel, basic_get(queue: queue, no_ack: false) do
      {basic_get_ok(delivery_tag: tag), content} -> [tag: tag, content: get_payload(content)]
      basic_get_empty() -> nil
    end
  end

  def set_qos(channel, prefetch_count \\ 1) do
    basic_qos_ok() = :amqp_channel.call channel, basic_qos(prefetch_count: prefetch_count)
    prefetch_count
  end

  def bind_queue(channel, queue, exchange, key \\ "") do
    queue_bind_ok() = :amqp_channel.call channel, queue_bind(queue: queue, exchange: exchange, routing_key: key)
  end

  def subscribe(channel, opts = %{queue: queue, noack: noack}) do
    sub = basic_consume(queue: queue, no_ack: noack)
    basic_consume_ok(consumer_tag: consumer_tag) = :amqp_channel.subscribe channel, sub, self
    consumer_tag
  end
  def subscribe(channel, queue), do: subscribe(channel, queue, self)

  def subscribe(channel, queue, pid) do
    sub = basic_consume(queue: queue)
    basic_consume_ok(consumer_tag: consumer_tag) = :amqp_channel.subscribe channel, sub, pid
    consumer_tag
  end

  def unsubscribe(channel, consumer_tag) do
    :amqp_channel.call channel, basic_cancel(consumer_tag: consumer_tag)
  end

  defp wait_confirmation(root, channel) do
    receive do
      basic_ack(delivery_tag: tag) ->
        send(root, {:message_confirmed, tag})
      basic_nack(delivery_tag: tag) ->
        send(root, {:message_lost, tag})
      after 15000 ->
        send(root, {:confirmation_timeout})
    end
    :amqp_channel.unregister_confirm_handler channel
  end

  defp get_payload(amqp_msg(payload: payload)), do: payload
end
