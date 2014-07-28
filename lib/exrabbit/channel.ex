defmodule Exrabbit.Channel do
  use Exrabbit.Defs

  alias Exrabbit.Connection, as: Conn

  @confirm_timeout 15000

  @type channel :: pid

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

  @doc """
  Switch the channel to confirmation or transactional mode.

  Once set, the mode cannot be changed.
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

  def ack(chan, basic_ack()=method) do
    :amqp_channel.call(chan, method)
  end

  def ack(chan, tag) do
    :amqp_channel.call(chan, basic_ack(delivery_tag: tag))
  end

  def nack(chan, basic_nack()=method) do
    :amqp_channel.call(chan, method)
  end

  def nack(chan, tag) do
    :amqp_channel.call(chan, basic_nack(delivery_tag: tag))
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
