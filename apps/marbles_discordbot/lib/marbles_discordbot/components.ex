defmodule MarblesDiscordbot.Components do
  @collection_per_page Marbles.Collection.per_page()

  def collection_components(page, total, sort) do
    max_page = max(1, div(total - 1, @collection_per_page) + 1)
    sort_str = sort_to_string(sort)

    [
      %{
        type: 1,
        components: [
          %{
            type: 2,
            style: 1,
            label: "Prev",
            custom_id: "coll_prev_#{page}_#{sort_str}",
            disabled: page <= 1
          },
          %{
            type: 2,
            style: 1,
            label: "Next",
            custom_id: "coll_next_#{page}_#{sort_str}",
            disabled: page >= max_page
          },
          %{type: 2, style: 2, label: "By Rarity", custom_id: "coll_sort_rarity_1"},
          %{type: 2, style: 2, label: "By Level", custom_id: "coll_sort_level_1"},
          %{type: 2, style: 2, label: "By Name", custom_id: "coll_sort_name_1"}
        ]
      }
    ]
  end

  defp sort_to_string(:rarity_level_name), do: "rarity"
  defp sort_to_string(:level_desc), do: "level"
  defp sort_to_string(:name_asc), do: "name"
  defp sort_to_string(_), do: "rarity"

  def packs_nav_components(packs, current_page, session_discord_user_id)
      when is_integer(session_discord_user_id) do
    prev_disabled = current_page <= 0
    next_disabled = current_page >= length(packs) - 1
    pack_id = (Enum.at(packs, current_page) || %{}).id
    sid = to_string(session_discord_user_id)

    [
      %{
        type: 1,
        components: [
          %{
            type: 2,
            style: 1,
            label: "Previous",
            custom_id: "packs_prev_#{current_page}_#{sid}",
            disabled: prev_disabled
          },
          %{
            type: 2,
            style: 1,
            label: "Next",
            custom_id: "packs_next_#{current_page}_#{sid}",
            disabled: next_disabled
          },
          %{
            type: 2,
            style: 3,
            label: "Pull",
            custom_id: "packs_open_#{pack_id}_#{sid}"
          }
        ]
      }
    ]
  end

  def pull_pack_action_row(pack_id, session_discord_user_id, label_one, label_ten)
      when is_integer(session_discord_user_id) do
    sid = to_string(session_discord_user_id)
    cid = pack_id |> to_string() |> String.replace("-", "")

    [
      %{
        type: 1,
        components: [
          %{
            type: 2,
            style: 1,
            label: trim_btn(label_one),
            custom_id: "pull1_#{sid}_#{cid}"
          },
          %{
            type: 2,
            style: 1,
            label: trim_btn(label_ten),
            custom_id: "pull10_#{sid}_#{cid}"
          }
        ]
      }
    ]
  end

  defp trim_btn(s) when is_binary(s) do
    if String.length(s) <= 80, do: s, else: String.slice(s, 0, 77) <> "..."
  end
end
