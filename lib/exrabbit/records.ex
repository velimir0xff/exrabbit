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

defmodule Exrabbit.Records.Props do
  defrecord :pbasic, :'P_basic', Record.extract(:'P_basic', from_lib: "rabbit_common/include/rabbit_framing.hrl")
end

defmodule Exrabbit.Records do
  defmacro __using__(_) do
    quote do
      import Exrabbit.Records.Props
      import Exrabbit.Records
    end
  end

  import Exrabbit.ExtractorUtils

  [
    :amqp_params_network,
  ] |> extract_all("amqp_client/include/amqp_client.hrl")

  [
    # Part of the public API
    :"exchange.declare",
    :"queue.declare",
    :"basic.deliver",
    :"basic.qos",

    # Exposed as Exrabbit functions
    :"exchange.delete",
    :"queue.purge",
    :"queue.delete",
    :"basic.publish", :"basic.get", :"basic.consume", :"basic.cancel",
    :"basic.ack", :"basic.nack", :"basic.reject",
    :"confirm.select",
    :"tx.select",

    # Used internally
    :"exchange.declare_ok", :"exchange.delete_ok",
    :"exchange.bind", :"exchange.bind_ok",

    :"queue.declare_ok", :"queue.bind", :"queue.bind_ok",
    :"queue.purge_ok", :"queue.delete_ok",

    :"basic.get_ok", :"basic.get_empty", :"basic.consume_ok",
    :"basic.cancel_ok", :"basic.qos_ok",

    :"confirm.select_ok",
    :"tx.select_ok",

    # Simply imported
    :"exchange.unbind", :"exchange.unbind_ok",
    :"queue.unbind", :"queue.unbind_ok",
  ] |> extract_all("rabbit_common/include/rabbit_framing.hrl")

  import Exrabbit.Records.Props
  defrecord :amqp_msg, [props: pbasic(), payload: ""]
end
