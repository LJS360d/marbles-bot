defmodule MarblesDiscordbot.Embeds do
  alias Nostrum.Struct.Embed
  alias Marbles.{IntegerDisplay, MarbleLabel, PackPullRules}
  alias Marbles.Economy.Currency
  require Logger

  @collection_per_page Marbles.Collection.per_page()

  def marble_embed(marble, opts \\ []) do
    image = marble_image_url(marble)
    thumbnail = if marble.team, do: Marbles.Assets.url_for_path(marble.team.logo_path), else: nil
    footer_text = Keyword.get(opts, :footer)

    title = MarbleLabel.pull_line(%{name: marble.name, rarity: marble.rarity})

    %Embed{}
    |> Embed.put_title(title)
    |> Embed.put_description(build_description(marble))
    |> Embed.put_color(rarity_color(marble.rarity || 1))
    |> maybe_put_image(image)
    |> maybe_put_thumbnail(thumbnail)
    |> maybe_put_footer(footer_text)
  end

  def currency_line(coins), do: "**#{IntegerDisplay.format(coins)}** #{Currency.coin_emoji()}"

  @spec pull_session_message_content(map(), term(), keyword()) :: String.t()
  def pull_session_message_content(user, pack, opts \\ []) do
    user_id = user.id
    coins = user.currency
    dust = Map.get(user, :dust) || 0
    pull_dust = Keyword.get(opts, :dust_last_pull, 0)

    wallet =
      currency_line(coins) <> " · **#{IntegerDisplay.format(dust)}** " <> Currency.dust_emoji()

    dup_note =
      if pull_dust > 0 do
        "\nDuplicates on last pull: **+#{IntegerDisplay.format(pull_dust)}** " <>
          Currency.dust_emoji()
      else
        ""
      end

    line1 = wallet <> dup_note

    case PackPullRules.pity_guarantee_line(pack, user_id) do
      nil -> line1
      pity -> line1 <> "\n" <> pity
    end
  end

  def pack_embed(pack, page, total) do
    expires =
      if pack.end_date do
        today = Date.utc_today()

        if Date.compare(pack.end_date, today) == :lt do
          "Expired"
        else
          days = Date.diff(pack.end_date, today)
          "Ends in #{IntegerDisplay.format(days)} days"
        end
      else
        "Permanent banner"
      end

    rules_text = PackPullRules.rules_summary_text(pack)

    description =
      "#{pack.description}\n\n #{IntegerDisplay.format(pack.cost || 0)} #{Currency.coin_emoji()} base cost · #{expires}\n\n#{rules_text}"

    banner_url = Marbles.Assets.url_for_path(pack.banner_path)

    embed =
      %Embed{}
      |> Embed.put_title(pack.name)
      |> Embed.put_description(description)
      |> Embed.put_image(banner_url)
      |> Embed.put_footer("Pack #{IntegerDisplay.format(page)}/#{IntegerDisplay.format(total)}")

    embed
  end

  @embed_field_value_limit 1024

  def collection_embed(items, page, total, sort, user \\ nil) do
    lines =
      Enum.map(items, fn um ->
        m = um.marble
        stars = MarbleLabel.stars(m.rarity)
        lv = IntegerDisplay.format(um.level || 1)
        "**#{m.name}** #{stars} Lv.#{lv}"
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
      |> Embed.put_title(
        "Your collection: #{IntegerDisplay.format(total)} marble#{if total != 1, do: "s", else: ""}"
      )
      |> Embed.put_footer(
        "Page #{IntegerDisplay.format(page)}/#{IntegerDisplay.format(total_pages)} · #{IntegerDisplay.format(total)} marbles #{sort_label && "· Sorted by #{sort_label}"}"
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
    stars = MarbleLabel.stars(marble.rarity)
    base = "**Rarity:** #{stars}#{team_line}\n\n#{marble.name} — #{marble.edition}"

    if is_map(marble.base_stats) and marble.base_stats != %{} do
      stats =
        marble.base_stats
        |> Enum.map(fn {k, v} ->
          val = if is_integer(v), do: IntegerDisplay.format(v), else: to_string(v)
          "#{k}: #{val}"
        end)
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

  def pull_banner_embed(pack) do
    desc =
      if pack.description && String.trim(pack.description) != "",
        do: pack.description,
        else: "*No description.*"

    banner_url =
      if pack.banner_path && pack.banner_path != "",
        do: Marbles.Assets.url_for_path(pack.banner_path),
        else: nil

    embed =
      %Embed{}
      |> Embed.put_title(pack.name)
      |> Embed.put_description(desc)

    if banner_url, do: Embed.put_image(embed, banner_url), else: embed
  end

  def ten_pull_result_embed(pack, marbles, discord_user)
      when is_list(marbles) and is_integer(discord_user.id) do
    rarities = Enum.map(marbles, &(&1.rarity || 1))
    max_r = if rarities == [], do: 1, else: Enum.max(rarities)

    base =
      %Embed{}
      |> Embed.put_title("10× pull — #{pack.name}")
      |> Embed.put_color(rarity_color(max_r))

    emb =
      Enum.with_index(marbles, 1)
      |> Enum.reduce(base, fn {m, idx}, acc ->
        line = MarbleLabel.pull_line(%{name: m.name, rarity: m.rarity})
        Embed.put_field(acc, "##{IntegerDisplay.format(idx)}", line, true)
      end)

    Embed.put_footer(emb, "Belongs to #{discord_user.global_name}")
  end

  def rarity_stars_string(rarity), do: MarbleLabel.stars(rarity)

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
