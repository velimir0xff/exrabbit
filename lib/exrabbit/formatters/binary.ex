defmodule Exrabbit.Formatter.BINARY do
  @behaviour Exrabbit.Formatter

  def encode(term), do: :erlang.term_to_binary(term)
  def decode(data) do
    try do
      {:ok, :erlang.binary_to_term(data)}
    catch
      _, reason ->
        {:error, reason}
    end
  end
end
