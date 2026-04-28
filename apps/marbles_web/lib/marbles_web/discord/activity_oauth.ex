defmodule MarblesWeb.Discord.ActivityOAuth do
  @type user_attrs :: %{
          required(:platform) => String.t(),
          required(:platform_id) => String.t(),
          required(:username) => String.t(),
          optional(:display_name) => String.t()
        }

  @spec exchange_code_for_user(String.t()) :: {:ok, user_attrs()} | {:error, term()}
  def exchange_code_for_user(code) when is_binary(code) and code != "" do
    with {:ok, token} <- exchange_code_for_token(code),
         {:ok, user} <- fetch_user(token.access_token) do
      {:ok,
       %{
         platform: "discord",
         platform_id: user.id,
         username: user.username,
         display_name: user.display_name
       }}
    end
  end

  def exchange_code_for_user(_), do: {:error, :missing_code}

  @spec exchange_code_for_token(String.t()) ::
          {:ok, %{access_token: String.t(), token_type: String.t()}} | {:error, term()}
  def exchange_code_for_token(code) when is_binary(code) and code != "" do
    with {:ok, client_id} <- fetch_config_value(:client_id),
         {:ok, client_secret} <- fetch_config_value(:client_secret) do
      body =
        %{
          "client_id" => client_id,
          "client_secret" => client_secret,
          "grant_type" => "authorization_code",
          "code" => code
        }
        |> maybe_put_redirect_uri()

      case Req.post(url: "https://discord.com/api/v10/oauth2/token", form: body) do
        {:ok, %Req.Response{status: 200, body: %{"access_token" => access_token} = resp}} ->
          {:ok, %{access_token: access_token, token_type: Map.get(resp, "token_type", "Bearer")}}

        {:ok, %Req.Response{status: status}} when status in [400, 401, 403] ->
          {:error, :invalid_code}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:token_exchange_failed, status}}

        {:error, reason} ->
          {:error, {:token_exchange_request_failed, reason}}
      end
    end
  end

  def exchange_code_for_token(_), do: {:error, :missing_code}

  @spec fetch_user(String.t()) ::
          {:ok, %{id: String.t(), username: String.t(), display_name: String.t()}}
          | {:error, term()}
  def fetch_user(access_token) when is_binary(access_token) and access_token != "" do
    headers = [{"authorization", "Bearer " <> access_token}]

    case Req.get(url: "https://discord.com/api/v10/users/@me", headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_discord_user(body)

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, :invalid_token}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:discord_user_fetch_failed, status}}

      {:error, reason} ->
        {:error, {:discord_user_request_failed, reason}}
    end
  end

  def fetch_user(_), do: {:error, :missing_access_token}

  @spec fetch_config_value(atom()) :: {:ok, String.t()} | {:error, :missing_configuration}
  defp fetch_config_value(key) do
    value =
      Application.get_env(:marbles_web, :discord_activity, [])
      |> Keyword.get(key)

    case value do
      current when is_binary(current) and current != "" -> {:ok, current}
      _ -> {:error, :missing_configuration}
    end
  end

  @spec maybe_put_redirect_uri(map()) :: map()
  defp maybe_put_redirect_uri(body) do
    redirect_uri =
      Application.get_env(:marbles_web, :discord_activity, [])
      |> Keyword.get(:redirect_uri)

    case redirect_uri do
      value when is_binary(value) and value != "" -> Map.put(body, "redirect_uri", value)
      _ -> body
    end
  end

  @spec parse_discord_user(map()) ::
          {:ok, %{id: String.t(), username: String.t(), display_name: String.t()}}
          | {:error, term()}
  defp parse_discord_user(%{"id" => id, "username" => username} = user)
       when is_binary(id) and is_binary(username) do
    display_name =
      case Map.get(user, "global_name") do
        value when is_binary(value) and value != "" -> value
        _ -> username
      end

    {:ok, %{id: id, username: username, display_name: display_name}}
  end

  defp parse_discord_user(_), do: {:error, :invalid_discord_user}
end
