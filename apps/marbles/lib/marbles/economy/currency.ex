defmodule Marbles.Economy.Currency do
  @moduledoc false

  @coin_emoji "🪙"
  @dust_emoji "✨"

  @spec coin_emoji() :: String.t()
  def coin_emoji, do: @coin_emoji

  @spec dust_emoji() :: String.t()
  def dust_emoji, do: @dust_emoji
end
