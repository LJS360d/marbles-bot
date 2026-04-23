defmodule MarblesWeb.Discord.GuildChannels do
  @moduledoc false

  @api_root "https://discord.com/api/v10"
  @text_types MapSet.new([0, 5])

  @type preview :: %{id: String.t(), name: String.t(), type: integer()}

  @doc "Whether a bot token is available (Nostrum env or DISCORD_BOT_TOKEN)."
  @spec bot_token?() :: boolean()
  def bot_token? do
    match?({:ok, _}, read_bot_token())
  end

  @doc "Fetches text/announcement-style channels for a guild (bot auth only)."
  @spec fetch_previews(String.t()) :: {:ok, [preview()]} | {:error, term()}
  def fetch_previews(guild_snowflake) when is_binary(guild_snowflake) do
    with {:ok, token} <- read_bot_token(),
         {:ok, raw} <- http_get_channels(guild_snowflake, token) do
      {:ok, normalize_previews(raw)}
    end
  end

  def fetch_previews(_), do: {:error, :missing_bot_token}

  defp read_bot_token do
    t = Application.get_env(:nostrum, :token) || System.get_env("DISCORD_BOT_TOKEN")

    if is_binary(t) and t != "",
      do: {:ok, t},
      else: {:error, :missing_bot_token}
  end

  defp http_get_channels(guild_id, token) do
    url = @api_root <> "/guilds/#{guild_id}/channels"

    case Req.get(url, headers: [{"authorization", "Bot #{token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, decode_list(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_list(body) when is_list(body), do: body

  defp decode_list(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp decode_list(_), do: []

  defp normalize_previews(list) do
    list
    |> Enum.filter(fn row ->
      t = type_of(row)
      t != nil and MapSet.member?(@text_types, t)
    end)
    |> Enum.map(fn row ->
      %{
        id: id_str(row["id"] || row[:id]),
        name: to_string(row["name"] || row[:name] || "channel"),
        type: type_of(row) || 0
      }
    end)
    |> Enum.uniq_by(& &1.id)
  end

  defp type_of(row), do: int_field(row["type"] || row[:type])

  defp id_str(v) when is_binary(v), do: v
  defp id_str(v) when is_integer(v), do: Integer.to_string(v)
  defp id_str(v), do: to_string(v)

  defp int_field(v) when is_integer(v), do: v

  defp int_field(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp int_field(_), do: nil
end
