defmodule Exrabbit.RPC.Client do
  @moduledoc """
  This module is designed to send RPC requests and handle responses from the
  handler.
  """
end

defmodule Exrabbit.RPC.Handler do
  @moduledoc """
  This module is designed to handle incoming RPC requests.
  """
end

#  def rpc(channel, exchange, routing_key, message, reply_to) do
#    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to), payload: message)
#  end
#
#  def rpc(channel, exchange, routing_key, message, reply_to, uuid) do
#    :amqp_channel.call channel, basic_publish(exchange: exchange, routing_key: routing_key), amqp_msg(props: pbasic(reply_to: reply_to, headers: ({"uuid", :longstr, uuid})  ), payload: message)
#  end
