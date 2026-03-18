defmodule MarblesDiscordbot.PullSession do
  @moduledoc false

  alias Nostrum.Api
  alias Nostrum.Api.Interaction, as: ApiInteraction
  alias Marbles.{Accounts, Catalog, PackPullRules}
  alias Marbles.Schema.User
  alias MarblesDiscordbot.Components

  def active_pack!(pack_id) do
    Enum.find(Catalog.list_active_packs(), fn p -> p.id == pack_id end)
  end

  def ensure_discord_user(platform_id, username) do
    Accounts.ensure_user(%{
      platform_id: to_string(platform_id),
      platform: "discord",
      username: username
    })
  end

  def action_row(%User{} = internal, pack, owner_discord_int) do
    Components.pull_pack_action_row(
      pack.id,
      owner_discord_int,
      PackPullRules.one_pull_button_label(pack, internal.id),
      PackPullRules.ten_pull_button_label(pack, internal.id)
    )
  end

  def clear_components_on_message(nil), do: :ok

  def clear_components_on_message(%{channel_id: ch} = msg) when not is_nil(ch) do
    _ = Api.edit_message(msg, %{components: []})
    :ok
  end

  def clear_components_on_message(_), do: :ok

  @spec discord_id(binary() | non_neg_integer()) :: non_neg_integer()
  def discord_id(id) when is_integer(id) and id >= 0, do: id

  def discord_id(id) when is_binary(id) do
    id
    |> String.to_integer()
    |> discord_id()
  end

  @spec user_mentions(non_neg_integer()) :: {:users, [non_neg_integer()]}
  def user_mentions(user_id) when is_integer(user_id) and user_id >= 0 do
    {:users, [user_id]}
  end

  def followup_with_pull_row(app_id, token, content, embeds, owner_int, components)
      when is_integer(owner_int) and owner_int >= 0 do
    ApiInteraction.create_followup_message(app_id, token, %{
      content: content || "",
      embeds: embeds,
      components: components,
      allowed_mentions: user_mentions(owner_int)
    })
  end

  def followup_ephemeral(app_id, token, content) do
    ApiInteraction.create_followup_message(app_id, token, %{content: content, flags: 64})
  end

  def insufficient_coins_response(needed, have, label \\ "this pull") do
    %{
      type: 4,
      data: %{
        content: "You need **#{needed}** coins for #{label}. You have #{have}.",
        flags: 64
      }
    }
  end

  def pack_unavailable_response do
    %{type: 4, data: %{content: "Pack unavailable.", flags: 64}}
  end

  def wrong_owner_response(owner_sid) do
    uid = discord_id(to_string(owner_sid))

    %{
      type: 4,
      data: %{
        content: "These pull buttons belong to <@#{owner_sid}>.",
        flags: 64,
        allowed_mentions: user_mentions(uid)
      }
    }
  end
end
