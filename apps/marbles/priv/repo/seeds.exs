alias Marbles.Schema.Pack
alias Marbles.Repo
alias Marbles.Schema.{Team, Marble, MarbleAsset, PackPullRule}
alias Marbles.PackPullRules
import Ecto.Query
require Logger

if is_nil(Process.whereis(Marbles.Repo)) do
  Application.ensure_all_started(:marbles)
end

data_path = fn filename ->
  Application.app_dir(:marbles, "priv/data/#{filename}")
end

teams_file = data_path.("teams.json")

if File.exists?(teams_file) do
  with {:ok, binary} <- File.read(teams_file),
       {:ok, teams_json} <- Jason.decode(binary) do
    Enum.each(teams_json, fn team_data ->
      team =
        %Team{}
        |> Team.changeset(team_data)
        |> Repo.insert(on_conflict: :nothing, conflict_target: :name, returning: true)
        |> case do
          {:ok, %Team{id: nil}} ->
            Repo.get_by!(Team, name: team_data["name"])

          {:ok, inserted_team} ->
            inserted_team

          {:error, changeset} ->
            Logger.error(
              "Could not insert team #{team_data["name"]}: #{inspect(changeset.errors)}"
            )

            nil
        end

      if team do
        infer_texture_path = fn assets ->
          case assets do
            assets when is_list(assets) ->
              case Enum.find(
                     assets,
                     &(is_map(&1) and &1["type"] == "splash" and is_binary(&1["filename"]))
                   ) do
                %{"filename" => path} ->
                  path |> Path.dirname() |> Path.join("texture.png")

                _ ->
                  case Enum.find(
                         assets,
                         &(is_map(&1) and &1["type"] == "thumbnail" and is_binary(&1["filename"]))
                       ) do
                    %{"filename" => path} ->
                      path |> Path.dirname() |> Path.join("texture.png")

                    _ ->
                      nil
                  end
              end

            _ ->
              nil
          end
        end

        Enum.each(team_data["marbles"] || [], fn marble_data ->
          texture_path =
            marble_data["texture_path"] || marble_data["texturePath"] ||
              infer_texture_path.(marble_data["assets"])

          full_data =
            marble_data
            |> Map.put("team_id", team.id)
            |> Map.put("base_stats", marble_data["base_stats"])
            |> Map.put("texture_path", texture_path)

          marble =
            %Marble{}
            |> Marble.changeset(full_data)
            |> Repo.insert!(on_conflict: :nothing)

          Enum.each(marble_data["assets"] || [], fn asset_data ->
            %MarbleAsset{}
            |> MarbleAsset.changeset(Map.put(asset_data, "marble_id", marble.id))
            |> Repo.insert!(on_conflict: :nothing)
          end)
        end)
      end
    end)

    Logger.info("Teams and Marbles seeded successfully.")
    Logger.info("Seeding process complete.")
  else
    {:error, reason} ->
      Logger.error("Failed to seed teams.json: #{inspect(reason)}")
  end
else
  raise "#{teams_file} not found, cannot proceed with seeding"
end

packs_file = data_path.("packs.json")

if File.exists?(packs_file) do
  with {:ok, binary} <- File.read(packs_file),
       {:ok, packs_json} <- Jason.decode(binary) do
    Enum.each(packs_json, fn pack_attrs ->
      pack =
        %Pack{}
        |> Pack.changeset(pack_attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: :name, returning: true)
        |> case do
          {:ok, %Pack{id: nil}} ->
            Repo.get_by!(Pack, name: pack_attrs["name"])

          {:ok, inserted} ->
            inserted

          {:error, changeset} ->
            Logger.error(
              "Could not insert pack #{pack_attrs["name"]}: #{inspect(changeset.errors)}"
            )

            nil
        end

      if pack do
        marbles_to_link =
          (pack_attrs["marbles"] || pack["marbles"] || [])
          |> Enum.map(fn m_query ->
            Repo.get_by(Marble, name: m_query["name"], edition: m_query["edition"])
          end)
          |> Enum.reject(&is_nil/1)

        Logger.info("found #{length(marbles_to_link)} marbles to link to pack #{pack.name}")

        pack
        |> Repo.preload(:marbles)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:marbles, marbles_to_link)
        |> Repo.update!()

        Logger.info("Pack '#{pack.name}' seeded with #{length(marbles_to_link)} marbles.")
      end
    end)

    Logger.info("Packs seeded successfully.")
  else
    {:error, reason} ->
      Logger.error("Failed to seed packs.json: #{inspect(reason)}")
  end
else
  raise "#{packs_file} not found, cannot proceed with seeding"
end

rules_file = data_path.("pack_rules.json")

if File.exists?(rules_file) do
  with {:ok, binary} <- File.read(rules_file),
       {:ok, groups} <- Jason.decode(binary) do
    Enum.each(groups, fn group ->
      pname = group["pack_name"]
      rules = group["rules"] || []

      case pname do
        nil ->
          Logger.warning("pack_rules.json entry missing pack_name, skipped")

        name when is_binary(name) ->
          pack = Repo.get_by(Pack, name: name)

          if pack do
            Repo.delete_all(from(r in PackPullRule, where: r.pack_id == ^pack.id))

            Enum.each(rules, fn row ->
              attrs = PackPullRules.row_attrs(pack.id, row)

              case %PackPullRule{}
                   |> PackPullRule.changeset(attrs)
                   |> Repo.insert() do
                {:ok, _} ->
                  :ok

                {:error, cs} ->
                  Logger.error("Pack rule for #{name}: #{inspect(row)} — #{inspect(cs.errors)}")
              end
            end)

            Logger.info("Pack pull rules seeded for '#{name}' (#{length(rules)} rules).")
          else
            Logger.warning("pack_rules.json: pack '#{name}' not found, skipped")
          end
      end
    end)
  else
    {:error, reason} ->
      Logger.error("Failed to read pack_rules.json: #{inspect(reason)}")
  end
else
  Logger.info("pack_rules.json not found, skipping pull rules seed.")
end
