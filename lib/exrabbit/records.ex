defmodule Exrabbit.ExtractorUtils do
  @moduledoc false

  defmacro extract_all(names, lib) do
    for name <- names do
      elixir_name = name |> Atom.to_string |> String.replace(".", "_") |> String.to_atom
      quote do
        import Record
        defrecord(unquote(elixir_name),
                  unquote(name),
                  Record.extract(unquote(name), from_lib: unquote(lib)))
      end
    end
  end
end

import Record

defmodule Exrabbit.Framing do
  defrecord :pbasic, :'P_basic', Record.extract(:'P_basic', from_lib: "rabbit_common/include/rabbit_framing.hrl")
end

defmodule Exrabbit.Defs do
  defmacro __using__(_) do
    quote do
      import Exrabbit.Framing
      import Exrabbit.Defs
    end
  end

  import Exrabbit.ExtractorUtils

  [
    :amqp_params_network,
  ] |> extract_all("amqp_client/include/amqp_client.hrl")

  [
    :"queue.declare", :"queue.declare_ok", :"queue.bind", :"queue.bind_ok",
    :"queue.purge", :"queue.purge_ok",

    :"basic.get", :"basic.get_ok", :"basic.get_empty", :"basic.ack",
    :"basic.consume", :"basic.consume_ok", :"basic.publish",
    :"basic.cancel", :"basic.cancel_ok", :"basic.deliver",

    :"exchange.declare", :"exchange.declare_ok", :"exchange.delete", :"exchange.delete_ok",
    :"exchange.bind", :"exchange.bind_ok", :"exchange.unbind", :"exchange.unbind_ok",

    :"basic.qos", :"basic.qos_ok", :"basic.nack",

    :"confirm.select", :"confirm.select_ok",

    :"tx.select", :"tx.select_ok",
  ] |> extract_all("rabbit_common/include/rabbit_framing.hrl")

  import Exrabbit.Framing
  defrecord :amqp_msg, [props: pbasic(), payload: ""]
end
