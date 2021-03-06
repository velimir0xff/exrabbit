defmodule Exrabbit.Consumer.DSL do
  @moduledoc ~S"""
  A DSL for writing GenServer consumers.

  In order to use this module, you need to call `use Exrabbit.Consumer.DSL,
  <options>` and `init/1`.

  The DSL is comprised by the following macros that are imported into the
  caller:

    * `init` - use this instead of `def init(...) do` to automatically
      initialize the consumer

    * `on/2` and `on/3` - those are used to define handlers for incoming AMQP
      messages

    * `on_error/2` - called when there was an error when parsing incoming
      message

  In addition, two public functions are added to the module, both of which take
  the GenServer pid (or name) as an argument:

    * `struct/1` - returns the `Exrabbit.Consumer` struct used by the GenServer

    * `shutdown/1` - shuts the GenServer down with the reason `:normal`

  ## Example

      defmodule TestConsumerAck do
        use Exrabbit.Consumer.DSL,
          exchange: exchange_declare(exchange: "test_topic_x", type: "topic"),
          new_queue: "dsl_auto_ack_queue",
          binding_key: "ackinator",
          no_ack: false

        use GenServer

        def start_link do
          GenServer.start_link(__MODULE__, [])
        end

        init [] do
          {:ok, nil}
        end

        on %Message{body: body}, nil do
          IO.puts "received and promised to acknowledge #{body}"
          {:ack, nil}
        end

        on %Message{body: body}=msg, nil, consumer do
          ack(consumer, msg)
          IO.puts "received and acknowledged #{body}"
          {:noreply, nil}
        end
      end

  """

  alias Exrabbit.Consumer

  @doc """
  Use the DSL in the calling module.

  ## Options

    * `import: <boolean>` - when `true` (the default), imports
      `Exrabbit.Consumer` and aliases `Exrabbit.Message` to just `Message`.

    * `format: <atom>` - the formatter to use when decoding incoming messages.

    * Any other option accepted by `Exrabbit.Consumer.new` and
      `Exrabbit.Consumer.subscribe`.

    * Alternatively, you may pass `config_name: <name>` option where `<name>`
      will be looked up in the application env. If it points to a keyword list
      or a map, it will be used as options for this module.

  """
  defmacro __using__(options) do
    imports = if Keyword.get(options, :import, true) do
      quote do
        import Exrabbit.Consumer
        alias Exrabbit.Message
      end
    end

    options = case Keyword.fetch(options, :config_name) do
      {:ok, name} -> {:env, name}
      :error -> {:final, options}
    end

    quote do
      use Exrabbit.Records

      unquote(imports)
      import unquote(__MODULE__), only: [init: 2, on: 3, on: 4, on_error: 3]
      @__Exrabbit_Consumer_DSL_options__ unquote(options)

      def struct(pid) do
        GenServer.call(pid, {unquote(__MODULE__), :struct})
      end

      def shutdown(pid) do
        GenServer.call(pid, {unquote(__MODULE__), :shutdown})
      end

      def handle_call({unquote(__MODULE__), :struct}, _from, {consumer, _}=state) do
        {:reply, consumer, state}
      end

      def handle_call({unquote(__MODULE__), :shutdown}, _from, state) do
        {:stop, :normal, :ok, state}
      end

      def handle_info(basic_consume_ok(), state) do
        {:noreply, state}
      end

      def handle_info(basic_cancel_ok(), state) do
        {:noreply, state}
      end

      def handle_info({basic_deliver(), amqp_msg()}=incoming_msg, {consumer, _}=state) do
        case Exrabbit.Util.parse_message(incoming_msg, format: consumer.format) do
          {:ok, msg} -> on_message(msg, state)
          {:error, reason} -> on_error(reason, state)
        end
      end

      def terminate(_reason, {consumer, _state}) do
        unquote(__MODULE__).shutdown_consumer(consumer)
      end

      defp on_error(_, state) do
        {:noreply, state}
      end

      defoverridable [on_error: 2]
    end
  end

  @doc """
  Defines the GenServer's `init/1` callback.

  Calling this instead of defining `init/1` manually lets the DSL open a
  connection and subscribe a new consumer to it that will be kept in the
  GenServer's state.

  ## Examples

      init [some, arguments] do
        state = {some, arguments}

        # consumer options can be added as an additional argument of the
        # standard tuple returned by GenServer's init callback
        {:ok, state, binding_key: "some key"}
      end

  """
  defmacro init(args, do: body) do
    quote do
      def init(unquote(args)) do
        tuple = unquote(body)
        unquote(__MODULE__).post_init(tuple, @__Exrabbit_Consumer_DSL_options__)
      end
    end
  end

  @doc ~S"""
  Handle an incoming AMQP message.

  The first argument will be the message, the second one will be the state (as
  initially returned from `init/1`).

  In addition to the normal return values expected from the `handle_info/2` it
  is possible to return one of the following, each of which will call the
  corresponding function on the internal consumer:

    * `{:ack, state[, timeout]}`
    * `{:reject, state[, timeout]}`
    * `{:nack, state[, timeout]}`

  Note that by default the consumer will not require ack's. You need to pass
  `no_ack: false` to it to enable ack's.

  ## Example

      on %Message{delivery_tag: tag, body: body}, state do
        IO.puts "Got '#{body}' with tag #{tag}"
        {:ack, state}
      end

  """
  defmacro on(message, state, do: body) do
    quote do
      defp on_message(unquote(message)=msg, {consumer, unquote(state)}) do
        tuple = unquote(body)
        unquote(__MODULE__).wrap_info_result(tuple, msg, consumer)
      end
    end
  end

  @doc """
  Handle an incoming AMQP message.

  This is similar to `on/3`. It takes an additional argument which will be the
  internal consumer struct. This is useful when you want to acknowledge a
  message as early as possible before processing it further.

  Note: you don't need to return the consumer in the final tuple, it will get
  appended automatically.

  ## Example

      on %Message{body: body}=msg, state, consumer do
        ack(consumer, msg)
        some_lengthy_processing(body)
        {:noreply, state}
      end

  """
  defmacro on(message, state, consumer, do: body) do
    quote do
      defp on_message(unquote(message)=msg, {unquote(consumer)=consumer, unquote(state)}) do
        tuple = unquote(body)
        unquote(__MODULE__).wrap_info_result(tuple, msg, consumer)
      end
    end
  end

  @doc ~S"""
  Handle a message parsing error.

  The first argument will be the reason, the second one will be the state (as
  initially returned from `init/1`).

  ## Example

      on_error reason, state do
        IO.puts :stderr, "Got error: #{inspect reason}"
        {:noreply, state}
      end

  """
  defmacro on_error(error, state, do: body) do
    quote do
      defp on_error(unquote(error), {consumer, unquote(state)}) do
        tuple = unquote(body)
        unquote(__MODULE__).wrap_info_result(tuple, nil, consumer)
      end
    end
  end

  @doc false
  def post_init({:ok, state, options}, base_options) when is_list(options) do
    new_state = init_consumer(state, base_options, options)
    {:ok, new_state}
  end

  def post_init({:ok, state, timeout, options}, base_options) when is_list(options) do
    new_state = init_consumer(state, base_options, options)
    {:ok, new_state, timeout}
  end

  def post_init({:ok, state}, base_options) do
    new_state = init_consumer(state, base_options, [])
    {:ok, new_state}
  end

  def post_init({:ok, state, timeout}, base_options) do
    new_state = init_consumer(state, base_options, [])
    {:ok, new_state, timeout}
  end

  def post_init(other, _), do: other


  @doc false
  def wrap_info_result({:noreply, state}, _, consumer) do
    {:noreply, {consumer, state}}
  end

  def wrap_info_result({:noreply, state, timeout}, _, consumer) do
    {:noreply, {consumer, state}, timeout}
  end

  def wrap_info_result({:ack, state}, msg, consumer) do
    Consumer.ack(consumer, msg)
    {:noreply, {consumer, state}}
  end

  def wrap_info_result({:ack, state, timeout}, msg, consumer) do
    Consumer.ack(consumer, msg)
    {:noreply, {consumer, state}, timeout}
  end

  def wrap_info_result({:nack, state}, msg, consumer) do
    Consumer.nack(consumer, msg)
    {:noreply, {consumer, state}}
  end

  def wrap_info_result({:nack, state, timeout}, msg, consumer) do
    Consumer.nack(consumer, msg)
    {:noreply, {consumer, state}, timeout}
  end

  def wrap_info_result({:reject, state}, msg, consumer) do
    Consumer.reject(consumer, msg)
    {:noreply, {consumer, state}}
  end

  def wrap_info_result({:reject, state, timeout}, msg, consumer) do
    Consumer.reject(consumer, msg)
    {:noreply, {consumer, state}, timeout}
  end

  def wrap_info_result(other, _, _), do: other


  @doc false
  def shutdown_consumer(consumer) do
    Consumer.shutdown(consumer)
  end

  ###

  defp init_consumer(state, base_options, init_options) do
    options = fetch_options(base_options) |> Enum.to_list |> Keyword.merge(init_options)
    consumer = Consumer.new(options) |> Consumer.subscribe(self(), [simple: false] ++ options)
    {consumer, state}
  end

  defp fetch_options({:final, options}), do: options

  defp fetch_options({:env, name}) do
    case Application.get_env(:exrabbit, name) do
      dict when is_list(dict) or is_map(dict) -> Enum.to_list(dict)
      other -> raise "Invalid Exrabbit.Consumer.DSL config for key #{inspect name}: #{inspect other}"
    end
  end
end
