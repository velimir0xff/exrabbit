defmodule Exrabbit.Connection do
  @moduledoc """
  This module exposes functions for opening and closing a connection to broker.
  """

  use Exrabbit.Records

  defstruct [conn: nil, chan: nil]
  alias __MODULE__

  @doc """
  Connect to a broker.

  Returns a new connection struct or fails.

  ## Options

    * `username: <string>` - username used for auth
    * `password: <string>` - password used for auth
    * `host: <string>` - broker host
    * `virtual_host: <string>` - the name of the virtual host in the broker
    * `heartbeat: <int>` - heartbeat interval in seconds (default: 1)
    * `with_chan: <bool>` - open a channel and puts it into the returned struct;
      default: `true`

  """
  @spec open(Keyword.t) :: %Connection{}
  def open(options \\ []) do
    conn_settings = Keyword.merge([
      username: get_default(:username),
      password: get_default(:password),
      host: get_default(:host) |> to_char_list,
      virtual_host: get_default(:virtual_host),
      heartbeat: get_default(:heartbeat),
    ], options)

    {:ok, conn} = :amqp_connection.start(amqp_params_network(
      username: conn_settings[:username],
      password: conn_settings[:password],
      host: conn_settings[:host],
      virtual_host: conn_settings[:virtual_host],
      heartbeat: conn_settings[:heartbeat]
    ))

    if Keyword.get(options, :with_chan, true) do
      %Connection{conn: conn, chan: open_channel(conn, options)}
    else
      %Connection{conn: conn}
    end
  end

  @doc """
  Close previously established connection.
  """
  @spec close(%Connection{}) :: :ok
  def close(%Connection{conn: conn, chan: chan}) do
    if chan do
      :ok = Exrabbit.Channel.close(chan)
    end
    :amqp_connection.close(conn)
  end

  ###

  defp open_channel(conn, options) do
    chan = Exrabbit.Channel.open(conn)
    case Keyword.fetch(options, :mode) do
      {:ok, mode} when mode in [:confirm, :tx] ->
        :ok = Exrabbit.Channel.set_mode(chan, mode)
      :error -> nil
    end
    chan
  end

  defp get_default(key) do
    Application.get_env(:exrabbit, key, default(key))
  end

  defp default(:username), do: "guest"
  defp default(:password), do: "guest"
  defp default(:host), do: "localhost"
  defp default(:virtual_host), do: "/"
  defp default(:heartbeat), do: 1
end
