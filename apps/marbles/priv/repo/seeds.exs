alias Marbles.Schema.Pack
alias Marbles.Repo
alias Marbles.Schema.{Team, Marble, MarbleAsset}
require Logger

Application.ensure_all_started(:marbles)

# Helper to find the absolute path to our data
data_path = fn filename ->
  Application.app_dir(:marbles, "priv/data/#{filename}")
end

# --- Seed Teams and Marbles ---
teams_file = data_path.("teams.json")

if File.exists?(teams_file) do
  # We use 'with' to chain the read and the decode.
  # If either fails, it drops to the 'else' block.
  with {:ok, binary} <- File.read(teams_file),
       {:ok, teams_json} <- Jason.decode(binary) do
    Enum.each(teams_json, fn team_data ->
      # Insert the team. If it exists, we fetch the existing one to get the ID.
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

      # Only proceed with marbles if we have a valid team struct
      if team do
        Enum.each(team_data["marbles"] || [], fn marble_data ->
          full_data =
            marble_data
            |> Map.put("team_id", team.id)
            |> Map.put("base_stats", marble_data["base_stats"])

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

# --- Packs ---
packs_file = data_path.("packs.json")

if File.exists?(packs_file) do
  with {:ok, binary} <- File.read(packs_file),
       {:ok, packs_json} <- Jason.decode(binary) do
    Enum.each(packs_json, fn pack_data ->
      pack_attrs =
        if pack_data["name"] == "Standard" do
          Map.merge(pack_data, %{"start_date" => ~D[2000-01-01], "end_date" => nil})
        else
          pack_data
        end

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
          (pack_attrs["marbles"] || pack_data["marbles"] || [])
          |> Enum.map(fn m_query ->
            Repo.get_by(Marble, name: m_query["name"], edition: m_query["edition"])
          end)
          # Remove entries if a marble wasn't found in DB
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
