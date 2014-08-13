defmodule Exrabbit.Channel do
  @moduledoc """
  This module exposes some channel-level AMQP methods.

  Mostly the functions that don't belong in neither `Exrabbit.Producer` nor
  `Exrabbit.Consumer` are kept here.
  """

  use Exrabbit.Records

  @type conn :: pid
  @type chan :: pid
  @type await_confirms_result :: :ok | {:error, :timeout} | {:error, :nack}

  @doc """
  Open a new channel on an established connection.

  Returns a new channel or fails.
  """
  @spec open(conn) :: chan | no_return
  def open(conn) when is_pid(conn) do
    {:ok, chan} = :amqp_connection.open_channel(conn)
    chan
  end

  @doc """
  Close previously opened channel.
  """
  @spec close(chan) :: :ok
  def close(chan), do: :amqp_channel.close(chan)

  @doc """
  Switch the channel to confirm-mode or tx-mode.

  Once set, the mode cannot be changed afterwards.
  """
  @spec set_mode(chan, :confirm | :tx) :: :ok

  def set_mode(chan, :confirm) do
    confirm_select_ok() = :amqp_channel.call(chan, confirm_select())
    :ok
  end

  def set_mode(chan, :tx) do
    tx_select_ok() = :amqp_channel.call(chan, tx_select())
    :ok
  end

  @doc """
  Set QoS (Quality of Service) on the channel.

  The second argument should be an `Exrabbit.Records.basic_qos` record.
  """
  @spec set_qos(chan, Exrabbit.Records.basic_qos) :: :ok
  def set_qos(chan, basic_qos()=qos) do
    basic_qos_ok() = :amqp_channel.call(chan, qos)
    :ok
  end

  @doc """
  Acknowledge a message.

  ## Options

    * `multiple: <boolean>` - when `true`, acknowledges all messages up to and
      including the current one in a single request; default: `false`

  """
  @spec ack(chan, binary) :: :ok
  @spec ack(chan, binary, Keyword.t) :: :ok
  def ack(chan, tag, opts \\ []) do
    method = basic_ack(
      delivery_tag: tag,
      multiple: Keyword.get(opts, :multiple, false)
    )
    :amqp_channel.call(chan, method)
  end

  @doc """
  Reject a message (RabbitMQ extension).

  ## Options

    * `multiple: <boolean>` - reject all messages up to and including the
      current one; default: `false`

    * `requeue: <boolean>` - put rejected messages back into the queue;
      default: `true`

  """
  @spec nack(chan, binary) :: :ok
  @spec nack(chan, binary, Keyword.t) :: :ok
  def nack(chan, tag, opts \\ []) do
    method = basic_nack(
      delivery_tag: tag,
      multiple: Keyword.get(opts, :multiple, false),
      requeue: Keyword.get(opts, :requeue, true)
    )
    :amqp_channel.call(chan, method)
  end

  @doc """
  Reject a message.

  ## Options

    * `requeue: <boolean>` - put the message back into the queue; default: `true`

  """
  @spec reject(chan, binary) :: :ok
  @spec reject(chan, binary, Keyword.t) :: :ok
  def reject(chan, tag, opts \\ []) do
    method = basic_reject(
      delivery_tag: tag,
      requeue: Keyword.get(opts, :requeue, true)
    )
    :amqp_channel.call(chan, method)
  end

  @doc """
  Await for message confirms.

  Returns `:ok` or `{:error, <reason>}` where `<reason>` can be one of the
  following:

    * `:timeout` - the timeout has run out before reply was received
    * `:nack` - at least one message hasn't been confirmed

  """
  @spec await_confirms(chan) :: await_confirms_result
  @spec await_confirms(chan, non_neg_integer) :: await_confirms_result
  def await_confirms(chan, timeout \\ confirm_timeout) do
    case :amqp_channel.wait_for_confirms(chan, timeout) do
      :timeout -> {:error, :timeout}
      false    -> {:error, :nack}
      true     -> :ok
    end
  end

  @doc """
  Redeliver all currently unacknowledged messages.

  ## Options

    * `requeue: <boolean>` - when `false` (default), the messages will be
      redelivered to the original consumer; when `true`, the messages will be
      put back into the queue and potentially be delivered to another consumer
      of that queue

  """
  @spec recover(chan) :: :ok
  @spec recover(chan, Keyword.t) :: :ok
  def recover(chan, options \\ []) do
    basic_recover_ok() = :amqp_channel.call(chan, basic_recover(requeue: Keyword.get(options, :requeue, false)))
    :ok
  end

  @doc """
  Commit current transaction.

  See http://www.rabbitmq.com/amqp-0-9-1-reference.html#tx.commit for details.
  """
  @spec commit(chan) :: :ok
  def commit(chan) do
    tx_commit_ok() = :amqp_channel.call(chan, tx_commit())
    :ok
  end

  @doc """
  Rollback current transaction.

  See http://www.rabbitmq.com/amqp-0-9-1-reference.html#tx.rollback for details.
  """
  @spec rollback(chan) :: :ok
  def rollback(chan) do
    tx_rollback_ok() = :amqp_channel.call(chan, tx_rollback())
    :ok
  end

  @doc """
  Delete an exchange.

  ## Options

    * `if_unused: <boolean>` - only delete the exchange if it has no queue
      bindings

  """
  @spec exchange_delete(chan, binary) :: :ok
  @spec exchange_delete(chan, binary, Keyword.t) :: :ok
  def exchange_delete(chan, name, options \\ []) when is_binary(name) do
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
  @spec queue_purge(chan, binary) :: non_neg_integer
  def queue_purge(chan, name) when is_binary(name) do
    method = queue_purge(queue: name)
    queue_purge_ok(message_count: cnt) = :amqp_channel.call(chan, method)
    cnt
  end

  @doc """
  Delete a queue.

  Returns the number of messages it contained.

  ## Options

    * `if_unused: <boolean>` - only delete the queue if it has no consumers
      (this options doesn't seem to work in the underlying Erlang client)

    * `if_empty: <boolean>` - only delete the queue if it has no messages

  """
  @spec queue_delete(chan, binary) :: non_neg_integer
  @spec queue_delete(chan, binary, Keyword.t) :: non_neg_integer
  def queue_delete(chan, name, options \\ []) when is_binary(name) do
    method = queue_delete(
      queue: name,
      if_unused: Keyword.get(options, :if_unused, false),
      if_empty: Keyword.get(options, :if_empty, false),
    )
    queue_delete_ok(message_count: cnt) = :amqp_channel.call(chan, method)
    cnt
  end

  defp confirm_timeout, do: Application.get_env(:exrabbit, :confirm_timeout, 15000)
end
