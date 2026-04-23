defmodule MarblesWeb.Admin.GuildChannelForms do
  @moduledoc false

  import Phoenix.Component, only: [to_form: 2]

  alias Marbles.Schema.Channel

  @type spawn_row :: %{channel: Channel.t(), form: term()}
  @type unused_row :: %{id: String.t(), name: String.t(), form: term()}

  @spec rows_saved([Channel.t()]) :: [spawn_row()]
  def rows_saved(channels) do
    Enum.map(channels, fn %Channel{id: id, spawn_rate: rate} = ch ->
      form =
        to_form(
          %{"rate" => format_rate(rate), "channel_id" => id},
          as: :spawn
        )

      %{channel: ch, form: form}
    end)
  end

  @spec rows_unused([Channel.t()], [map()]) :: [unused_row()]
  def rows_unused(db_channels, fetched) do
    known = MapSet.new(Enum.map(db_channels, & &1.id))

    fetched
    |> Enum.reject(&MapSet.member?(known, &1.id))
    |> Enum.map(fn %{id: id, name: name} ->
      form =
        to_form(
          %{"rate" => "0", "channel_id" => id, "channel_name" => name},
          as: :unused_spawn
        )

      %{id: id, name: name, form: form}
    end)
  end

  @spec parse_spawn_percent(String.t()) :: {:ok, float()} | {:error, :invalid_rate}
  def parse_spawn_percent(str) when is_binary(str) do
    str = String.trim(str)

    cond do
      str == "" ->
        {:ok, 0.0}

      true ->
        case Float.parse(str) do
          {f, _} -> {:ok, f |> max(0.0) |> min(100.0)}
          :error -> {:error, :invalid_rate}
        end
    end
  end

  @spec parse_spawn_percent(term()) :: {:ok, float()} | {:error, :invalid_rate}
  def parse_spawn_percent(_), do: {:error, :invalid_rate}

  defp format_rate(rate) when is_float(rate), do: :erlang.float_to_binary(rate, decimals: 2)
  defp format_rate(rate) when is_integer(rate), do: Integer.to_string(rate)
  defp format_rate(_), do: "0"
end
