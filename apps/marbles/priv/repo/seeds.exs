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
            |> Map.put("base_stats", marble_data["stats"])

          Enum.each(marble_data["assets"] || [], fn asset_data ->
            %MarbleAsset{}
            |> MarbleAsset.changeset(Map.put(asset_data, "marble_id", marble_data.id))
            |> Repo.insert!(on_conflict: :nothing)
          end)

          %Marble{}
          |> Marble.changeset(full_data)
          |> Repo.insert(on_conflict: :nothing, conflict_target: [:name, :edition])
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
  Logger.warning("#{teams_file} not found, skipping seeding.")
end
