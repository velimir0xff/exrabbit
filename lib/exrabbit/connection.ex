defmodule Exrabbit.Connection do
  use Exrabbit.Defs

  @doc """
  Connect to a broker.

  Returns a new connection or fails.

  ## Options

    * `username: <string>` - username used for auth
    * `password: <string>` - password used for auth
    * `host: <string>` - broker host
    * `virtual_host: <string>` - the name of the virtual host in the broker
    * `heartbeat: <int>` - heartbeat interval in seconds (default: 1)

  """
  def open(options \\ []) do
    conn_settings = Keyword.merge([
      username: get_default(:username),
      password: get_default(:password),
      host: get_default(:host) |> to_char_list,
      virtual_host: "/",
      heartbeat: 1
    ], options)

    {:ok, conn} = :amqp_connection.start(amqp_params_network(
      username: conn_settings[:username],
      password: conn_settings[:password],
      host: conn_settings[:host],
      virtual_host: conn_settings[:virtual_host],
      heartbeat: conn_settings[:heartbeat]
    ))
    conn
  end

  @doc """
  Close previously established connection.
  """
  def close(conn), do: :amqp_connection.close(conn)

  ###

  defp get_default(key) do
    Application.get_env(:exrabbit, key, default(key))
  end

  defp default(:host), do: "localhost"
  defp default(:username), do: "guest"
  defp default(:password), do: "guest"
end
