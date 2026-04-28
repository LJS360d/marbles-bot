defmodule MarblesDiscordbot.InteractionResponse do
  @moduledoc false

  @type response :: %{required(:type) => integer(), required(:data) => map()}

  @spec message(String.t()) :: response()
  def message(content), do: %{type: 4, data: %{content: content}}

  @spec update_message(String.t()) :: response()
  def update_message(content), do: %{type: 7, data: %{content: content}}

  @spec ephemeral(String.t()) :: response()
  def ephemeral(content), do: %{type: 4, data: %{content: content, flags: 64}}
end
