defmodule Exrabbit.Utils do
  use Exrabbit.Defs

  def parse_message({basic_deliver(delivery_tag: tag), amqp_msg(props: pbasic(reply_to: nil), payload: payload)}), do: {tag, payload}
  def parse_message({basic_deliver(delivery_tag: tag), amqp_msg(props: pbasic(reply_to: reply_to), payload: payload)}), do: {tag, payload, reply_to}
  def parse_message({basic_deliver(delivery_tag: tag), amqp_msg(payload: payload)}), do: {:message,tag, payload}
  def parse_message(basic_cancel_ok()), do: nil
  def parse_message(basic_consume_ok()), do: nil
  def parse_message(exchange_declare_ok()), do: nil
  def parse_message(exchange_delete_ok()), do: nil
  def parse_message(exchange_bind_ok()), do: nil
  def parse_message(exchange_unbind_ok()), do: nil
  def parse_message(basic_qos_ok()), do: nil

  def parse_message(basic_cancel()) do
    {:error, :queue_killed}
  end

  def parse_message(_) do
    {:error, :unknown_message}
  end
end
