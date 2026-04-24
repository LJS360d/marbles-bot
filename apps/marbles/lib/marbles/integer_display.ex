defmodule Marbles.IntegerDisplay do
  @moduledoc false

  @spec format(integer() | nil) :: String.t()
  def format(nil), do: "0"

  def format(n) when is_integer(n) do
    sign = if n < 0, do: "-", else: ""
    abs_str = n |> abs() |> Integer.to_string()

    body =
      if String.length(abs_str) > 4 do
        abs_str
        |> String.graphemes()
        |> Enum.reverse()
        |> Enum.chunk_every(3)
        |> Enum.map(&(&1 |> Enum.reverse() |> Enum.join()))
        |> Enum.reverse()
        |> Enum.join("'")
      else
        abs_str
      end

    sign <> body
  end
end
