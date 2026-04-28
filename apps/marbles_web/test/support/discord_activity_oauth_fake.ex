defmodule MarblesWeb.TestSupport.DiscordActivityOAuthFake do
  @spec exchange_code_for_user(String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code_for_user("good") do
    {:ok,
     %{
       platform: "discord",
       platform_id: "activity-user-1001",
       username: "activity-user",
       display_name: "Activity User"
     }}
  end

  def exchange_code_for_user(_), do: {:error, :invalid_code}
end
