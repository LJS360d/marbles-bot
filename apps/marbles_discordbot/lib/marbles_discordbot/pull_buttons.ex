defmodule MarblesDiscordbot.PullButtons do
  @moduledoc false

  def parse(cid) when is_binary(cid) do
    parsed =
      cond do
        String.starts_with?(cid, "pull10_") -> {:ok, 10, String.slice(cid, 7..-1//1)}
        String.starts_with?(cid, "pull1_") -> {:ok, 1, String.slice(cid, 6..-1//1)}
        true -> :error
      end

    case parsed do
      :error ->
        :error

      {:ok, mult, rest} ->
        case Regex.run(~r/^(\d+)_([0-9a-fA-F]{32})$/, rest) do
          [_, owner_snowflake, hex32] ->
            case uuid_from_compact32(hex32) do
              nil -> :error
              pack_id -> {:ok, mult, owner_snowflake, pack_id}
            end

          _ ->
            :error
        end
    end
  end

  defp uuid_from_compact32(h) do
    h = String.downcase(h)

    if String.length(h) == 32 and Regex.match?(~r/^[0-9a-f]+$/, h) do
      formatted =
        String.slice(h, 0, 8) <>
          "-" <>
          String.slice(h, 8, 4) <>
          "-" <>
          String.slice(h, 12, 4) <>
          "-" <>
          String.slice(h, 16, 4) <>
          "-" <>
          String.slice(h, 20, 12)

      case Ecto.UUID.cast(formatted) do
        {:ok, id} -> id
        :error -> nil
      end
    else
      nil
    end
  end
end
