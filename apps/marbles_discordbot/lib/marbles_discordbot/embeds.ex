defmodule MarblesDiscordbot.Embeds do
  alias Nostrum.Struct.Embed
  require Logger

  @collection_per_page Marbles.Collection.per_page()

  def marble_embed(marble, opts \\ []) do
    image = marble_image_url(marble)
    thumbnail = if marble.team, do: Marbles.Assets.url_for_path(marble.team.logo_path), else: nil
    footer_text = Keyword.get(opts, :footer)

    # Start with a base embed and chain updates
    %Embed{}
    |> Embed.put_title(marble.name)
    |> Embed.put_description(build_description(marble))
    |> Embed.put_color(rarity_color(marble.rarity || 1))
    |> maybe_put_image(image)
    |> maybe_put_thumbnail(thumbnail)
    |> maybe_put_footer(footer_text)
  end

  def pack_embed(pack, page, total) do
    count = length(pack.marbles || [])

    expires =
      if pack.end_date do
        today = Date.utc_today()

        if Date.compare(pack.end_date, today) == :lt do
          "Expired"
        else
          days = Date.diff(pack.end_date, today)
          "Expires in #{days} days"
        end
      else
        "No expiry"
      end

    description =
      "#{pack.description || "No description."}\n\n**#{count}** marbles · #{pack.cost} coins · #{expires}"

    banner_url = Marbles.Assets.url_for_path(pack.banner_path)

    embed =
      %Embed{}
      |> Embed.put_title(pack.name)
      |> Embed.put_description(description)
      |> Embed.put_image(banner_url)
      |> Embed.put_footer("Pack #{page}/#{total}")

    embed
  end

  @embed_field_value_limit 1024

  def collection_embed(items, page, total, sort, user \\ nil) do
    lines =
      Enum.map(items, fn um ->
        m = um.marble
        stars = String.duplicate("⭐", m.rarity) <> String.duplicate("☆", 3 - m.rarity)
        "**#{m.name}** #{stars} Lv.#{um.level}"
      end)

    field_values =
      lines
      |> Enum.chunk_while(
        "",
        fn line, acc ->
          new_acc = if acc == "", do: line, else: acc <> "\n" <> line

          if String.length(new_acc) <= @embed_field_value_limit,
            do: {:cont, new_acc},
            else: {:cont, acc, line}
        end,
        fn
          "" -> {:cont, ""}
          acc -> {:cont, acc, ""}
        end
      )
      |> Enum.reject(&(&1 == ""))

    sort_label =
      case sort do
        :level_desc -> "Level"
        :name_asc -> "Name"
        :rarity_level_name -> "Rarity"
        _ -> nil
      end

    total_pages = max(1, ceil(total / @collection_per_page))

    embed =
      %Embed{}
      |> Embed.put_title("Your collection: #{total} marble#{if total != 1, do: "s", else: ""}")
      |> Embed.put_footer(
        "Page #{page}/#{total_pages} · #{total} marbles #{sort_label && "· Sorted by #{sort_label}"}"
      )

    embed =
      field_values
      |> Enum.with_index()
      |> Enum.reduce(embed, fn {value, idx}, acc ->
        Embed.put_field(acc, if(idx == 0, do: "Marbles", else: "\u200b"), value, false)
      end)

    maybe_put_thumbnail(embed, user && Nostrum.Struct.User.avatar_url(user))
  end

  # Helper to build the description string
  defp build_description(marble) do
    team_line = if marble.team, do: "\n**Team:** #{marble.team.name}", else: ""
    base = "**Rarity:** #{marble.rarity}#{team_line}\n\n#{marble.name} — #{marble.edition}"

    if is_map(marble.base_stats) and marble.base_stats != %{} do
      stats =
        marble.base_stats
        |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
        |> Enum.join(", ")

      base <> "\n*Stats: #{stats}*"
    else
      base
    end
  end

  # Custom helpers to handle nil/empty URLs safely
  defp maybe_put_image(embed, nil), do: embed
  defp maybe_put_image(embed, ""), do: embed
  defp maybe_put_image(embed, url), do: Embed.put_image(embed, url)

  defp maybe_put_thumbnail(embed, nil), do: embed
  defp maybe_put_thumbnail(embed, ""), do: embed
  defp maybe_put_thumbnail(embed, url), do: Embed.put_thumbnail(embed, url)

  defp maybe_put_footer(embed, nil), do: embed
  defp maybe_put_footer(embed, text), do: Embed.put_footer(embed, text, nil)

  def rarity_color(1), do: 0x808080
  def rarity_color(2), do: 0x00FF00
  def rarity_color(3), do: 0x0080FF
  def rarity_color(_), do: 0x9B59B6

  def marble_image_url(marble) do
    asset =
      (marble.assets || [])
      |> Enum.find(fn a -> a.type in [:splash, "splash"] end) ||
        List.first(marble.assets || [])

    if asset && asset.filename, do: Marbles.Assets.url_for_path(asset.filename), else: nil
  end
end
