defmodule Exrabbit.Formatter do
  use Behaviour

  @doc """
  Encode the given term as a binary for transimitting.
  """
  defcallback encode(term :: term) :: binary

  @doc """
  Decode the given binary into a term.
  """
  defcallback decode(data :: binary) :: {:ok, term} | {:error, term}
end
