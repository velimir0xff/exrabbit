defmodule Exrabbit.Consumer.DSL do
  alias Exrabbit.Consumer

  defmacro __using__(options) do
    imports = if Keyword.get(options, :import, true) do
      quote do
        import Exrabbit.Consumer
        alias Exrabbit.Message
      end
    end

    quote do
      use Exrabbit.Records

      unquote(imports)
      import unquote(__MODULE__), only: [init: 2, on: 3, on: 4]
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

      def handle_info({basic_deliver(
                          consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
                          exchange: exchange, routing_key: key),
                       amqp_msg(props: props, payload: body)}, state) do
        msg = %Exrabbit.Message{
          consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
          exchange: exchange, routing_key: key, message: body, props: props,
        }
        on_message(msg, state)
      end

      def terminate(_reason, {consumer, _state}) do
        unquote(__MODULE__).shutdown_consumer(consumer)
      end
    end
  end

  defmacro init(args, do: body) do
    quote do
      def init(unquote(args)) do
        tuple = unquote(body)
        unquote(__MODULE__).post_init(tuple, @__Exrabbit_Consumer_DSL_options__)
      end
    end
  end

  defmacro on(pattern, state, do: body) do
    quote do
      defp on_message(unquote(pattern)=msg, {consumer, unquote(state)}) do
        tuple = unquote(body)
        unquote(__MODULE__).wrap_info_result(tuple, msg, consumer)
      end
    end
  end

  defmacro on(pattern, state, consumer, do: body) do
    quote do
      defp on_message(unquote(pattern)=msg, {unquote(consumer)=consumer, unquote(state)}) do
        tuple = unquote(body)
        unquote(__MODULE__).wrap_info_result(tuple, msg, consumer)
      end
    end
  end

  @doc false
  def post_init({:ok, state, options}, base_options) when is_list(options) do
    new_state = init_consumer(state, Keyword.merge(base_options, options))
    {:ok, new_state}
  end

  def post_init({:ok, state, timeout, options}, base_options) when is_list(options) do
    new_state = init_consumer(state, Keyword.merge(base_options, options))
    {:ok, new_state, timeout}
  end

  def post_init({:ok, state}, base_options) do
    new_state = init_consumer(state, base_options)
    {:ok, new_state}
  end

  def post_init({:ok, state, timeout}, base_options) do
    new_state = init_consumer(state, base_options)
    {:ok, new_state, timeout}
  end

  def post_init(other, _), do: other


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

  def wrap_info_result(other, _, _), do: other


  def shutdown_consumer(consumer) do
    Consumer.shutdown(consumer)
  end

  ###

  defp init_consumer(state, options) do
    consumer = Consumer.new(options) |> Consumer.subscribe(self(), [simple: false] ++ options)
    {consumer, state}
  end
end
