defmodule MarblesDiscordbot.DiscordUsername do
  @moduledoc false

  @doc """
  Resolves a Discord user's login `username` for `Accounts.ensure_user/1` and related flows.

  Prefers a non-empty `username` from `Nostrum.Cache.UserCache`; on miss or empty value,
  calls `Nostrum.Api.User.get/1`. Falls back to trimmed `global_name`, then the numeric
  snowflake string (never placeholder error strings).
  """
  @spec resolve_login(pos_integer()) :: String.t()
  def resolve_login(user_id) when is_integer(user_id) do
    user_id |> fetch_user() |> login_from_user(user_id)
  end

  defp fetch_user(user_id) do
    case Nostrum.Cache.UserCache.get(user_id) do
      {:ok, %{username: u} = cached} when is_binary(u) and u != "" ->
        cached

      _ ->
        case Nostrum.Api.User.get(user_id) do
          {:ok, u} -> u
          _ -> nil
        end
    end
  end

  defp login_from_user(user, user_id) do
    u = user && user.username
    g = user && user.global_name

    case {u, g} do
      {name, _} when is_binary(name) and name != "" ->
        name

      {_, disp} when is_binary(disp) ->
        case String.trim(disp) do
          "" -> to_string(user_id)
          trimmed -> trimmed
        end

      _ ->
        to_string(user_id)
    end
  end
end
