defmodule Exrabbit.Channel do
  use Exrabbit.Records

  @confirm_timeout 15000

  @type channel :: pid

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
  """
  @spec close(channel) :: :ok
  def close(chan), do: :amqp_channel.close(chan)

  @doc """
  Switch the channel to confirm-mode or tx-mode.

  Once set, the mode cannot be changed afterwards.
  """
  @spec set_mode(channel, :confirm | :tx) :: :ok

  def set_mode(chan, :confirm) do
    confirm_select_ok() = :amqp_channel.call(chan, confirm_select())
    :ok
  end

  def set_mode(chan, :tx) do
    tx_select_ok() = :amqp_channel.call(chan, tx_select())
    :ok
  end

  def set_qos(chan, basic_qos()=qos) do
    basic_qos_ok() = :amqp_channel.call(chan, qos)
    :ok
  end

  def ack(chan, tag, opts \\ []) do
    method = basic_ack(
      delivery_tag: tag,
      multiple: Keyword.get(opts, :multiple, false)
    )
    :amqp_channel.call(chan, method)
  end

  def nack(chan, tag, opts \\ []) do
    method = basic_nack(
      delivery_tag: tag,
      multiple: Keyword.get(opts, :multiple, false),
      requeue: Keyword.get(opts, :requeue, true)
    )
    :amqp_channel.call(chan, method)
  end

  def reject(chan, tag, opts \\ []) do
    method = basic_reject(
      delivery_tag: tag,
      requeue: Keyword.get(opts, :requeue, true)
    )
    :amqp_channel.call(chan, method)
  end

  def exchange_delete(chan, name, options \\ []) do
    method = exchange_delete(
      exchange: name,
      if_unused: Keyword.get(options, :if_unused, false),
    )
    exchange_delete_ok() = :amqp_channel.call(chan, method)
    :ok
  end

  @doc """
  Clear a queue.

  Returns the number of messages it contained.
  """
  def queue_purge(chan, name) do
    method = queue_purge(queue: name)
    queue_purge_ok(message_count: cnt) = :amqp_channel.call(chan, method)
    cnt
  end

  @doc """
  Delete a queue.

  Returns the number of messages it contained.
  """
  def queue_delete(chan, name, options \\ []) do
    method = queue_delete(
      queue: name,
      if_unused: Keyword.get(options, :if_unused, false),
      if_empty: Keyword.get(options, :if_empty, false),
    )
    queue_delete_ok(message_count: cnt) = :amqp_channel.call(chan, method)
    cnt
  end

  def await_confirms(chan, timeout \\ @confirm_timeout) do
    case :amqp_channel.wait_for_confirms(chan, timeout) do
      :timeout -> {:error, :timeout}
      false    -> {:error, :nack}
      true     -> :ok
    end
  end

  def rpc(channel, exchange, routing_key, message, reply_to) do
    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to), payload: message)
  end

  def rpc(channel, exchange, routing_key, message, reply_to, uuid) do
    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to, headers: ({"uuid", :longstr, uuid})  ), payload: message)
  end

end
