defmodule Exrabbit.Connection do
  use Exrabbit.Records

  defstruct [connection: nil, channel: nil]
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
    * `with_channel: <bool>` - when `true`, also opens a channel and puts it
      into the returned struct

  """
  def open(options \\ []) do
    conn_settings = Keyword.merge([
      username: get_default(:username),
      password: get_default(:password),
      host: get_default(:host) |> to_char_list,
      virtual_host: get_default(:virtual_host),
      heartbeat: get_default(:hearbeat),
    ], options)

    {:ok, conn} = :amqp_connection.start(amqp_params_network(
      username: conn_settings[:username],
      password: conn_settings[:password],
      host: conn_settings[:host],
      virtual_host: conn_settings[:virtual_host],
      heartbeat: conn_settings[:heartbeat]
    ))

    if Keyword.get(options, :with_channel, true) do
      %Connection{connection: conn, channel: open_channel(conn, options)}
    else
      %Connection{connection: conn}
    end
  end

  defp open_channel(conn, options) do
    chan = Exrabbit.Channel.open(conn)
    case Keyword.fetch(options, :mode) do
      {:ok, mode} when mode in [:confirm, :tx] ->
        :ok = Exrabbit.Channel.set_mode(chan, mode)
      :error -> nil
    end
    chan
  end

  @doc """
  Close previously established connection.
  """
  def close(%Connection{connection: conn, channel: chan}) do
    if chan do
      :ok = Exrabbit.Channel.close(chan)
    end
    :amqp_connection.close(conn)
  end

  ###

  defp get_default(key) do
    Application.get_env(:exrabbit, key, default(key))
  end

  defp default(:username), do: "guest"
  defp default(:password), do: "guest"
  defp default(:host), do: "localhost"
  defp default(:virtual_host), do: "/"
  defp default(:hearbeat), do: 1
end
