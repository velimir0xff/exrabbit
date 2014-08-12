defmodule Exrabbit.Formatter.JSON do
  @behaviour Exrabbit.Formatter

  def encode(term), do: Jazz.encode!(term)
  def decode(data) do
    case Jazz.decode(data) do
      {:ok, term} -> {:ok, term}
      {:error, reason} -> {:error, reason}
      {:error, a, b} -> {:error, {a, b}}
    end
  end
end
