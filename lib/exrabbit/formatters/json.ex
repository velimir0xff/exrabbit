defmodule Exrabbit.Formatter.JSON do
  @behaviour Exrabbit.Formatter

  def encode(term), do: Jazz.encode!(term)
  def decode(data), do: Jazz.decode(data)
end
