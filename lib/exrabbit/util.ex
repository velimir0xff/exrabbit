defmodule Exrabbit.Util do
  use Exrabbit.Records

  alias Exrabbit.Message

  @typep message :: {Exrabbit.Records.basic_deliver(), Exrabbit.Records.amqp_msg()}
                  | {Exrabbit.Records.basic_get_ok(), Exrabbit.Records.amqp_msg()}

  @doc """
  Parse a message coming from the subscriber or `get` function into `
  %Message{}` struct according to the specified format.
  """
  @spec parse_message(message) :: {:ok, %Message{}}
  @spec parse_message(message, format: atom) :: {:ok, %Message{}} | {:error, term}

  def parse_message(message, options \\ [])

  def parse_message({
    basic_deliver(consumer_tag: ctag, delivery_tag: dtag,
                  redelivered: rflag, exchange: exchange, routing_key: key),
    amqp_msg(props: props, payload: body)
  }, options) do
    case decode_body(body, Keyword.get(options, :format, false)) do
      {:ok, term} ->
        msg = %Message{
          consumer_tag: ctag, delivery_tag: dtag, redelivered: rflag,
          exchange: exchange, routing_key: key, body: term, props: props,
        }
        {:ok, msg}
      {:error, _reason}=error -> error
    end
  end

  def parse_message({
    basic_get_ok(delivery_tag: dtag,
                 redelivered: rflag, exchange: exchange, routing_key: key,
                 message_count: cnt),
    amqp_msg(props: props, payload: body)
  }, options) do
    case decode_body(body, Keyword.get(options, :format, false)) do
      {:ok, term} ->
        msg = %Message{
          delivery_tag: dtag, redelivered: rflag, exchange: exchange,
          routing_key: key, message_count: cnt, body: term, props: props,
        }
        {:ok, msg}
      {:error, _reason}=error -> error
    end
  end

  @doc false
  def encode_body(message, nil), do: message

  def encode_body(message, false) do
    case Application.fetch_env(:exrabbit, :format) do
      {:ok, format} -> do_encode_body(message, format)
      :error -> message
    end
  end

  def encode_body(message, format) when is_atom(format) do
    do_encode_body(message, format)
  end

  defp do_encode_body(message, format) do
    mod = get_formatter_module(format)
    mod.encode(message)
  end

  @doc false
  def decode_body(data, nil), do: {:ok, data}

  def decode_body(data, false) do
    case Application.fetch_env(:exrabbit, :format) do
      {:ok, format} -> do_decode_body(data, format)
      :error -> {:ok, data}
    end
  end

  def decode_body(data, format) when is_atom(format) do
    do_decode_body(data, format)
  end

  defp do_decode_body(data, format) do
    mod = get_formatter_module(format)
    mod.decode(data)
  end

  defp get_formatter_module(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> _ -> atom
      reference -> Module.concat(Exrabbit.Formatter, String.upcase(reference))
    end
  end
end
