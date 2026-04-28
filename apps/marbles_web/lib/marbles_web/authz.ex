defmodule MarblesWeb.Authz do
  @moduledoc false

  alias Marbles.Accounts
  alias Marbles.Schema.User

  @type auth_requirement :: :user | :owner | :server_admin_or_owner

  @spec fetch_current_user(nil | String.t() | integer()) :: User.t() | nil
  def fetch_current_user(nil), do: nil
  def fetch_current_user(user_id), do: Accounts.get_user(user_id)

  @spec authorize(User.t() | nil, auth_requirement()) :: :ok | {:error, :unauthorized}
  def authorize(%User{}, :user), do: :ok
  def authorize(%User{role: :owner}, :owner), do: :ok
  def authorize(%User{role: :owner}, :server_admin_or_owner), do: :ok
  def authorize(%User{role: :server_admin}, :server_admin_or_owner), do: :ok
  def authorize(_, _), do: {:error, :unauthorized}
end
