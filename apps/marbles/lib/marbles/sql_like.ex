defmodule Marbles.SqlLike do
  @moduledoc false

  @spec escape_like_fragment(String.t()) :: String.t()
  def escape_like_fragment(q) when is_binary(q) do
    q
    |> String.replace("\\", "")
    |> String.replace("%", "")
    |> String.replace("_", "")
  end
end
