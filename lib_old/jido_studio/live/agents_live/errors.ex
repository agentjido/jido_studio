defmodule JidoStudio.Live.AgentsLive.Errors do
  @moduledoc false

  def format_dispatch_error({:invalid_json, message}), do: "Invalid JSON: " <> message

  def format_dispatch_error({:payload_validation_failed, reason}),
    do: "Payload validation failed: " <> inspect(reason)

  def format_dispatch_error(reason), do: inspect(reason)

  def chat_unavailable_message(:credentials_missing) do
    "Chat needs provider credentials. Open Interact or add API keys in Settings."
  end

  def chat_unavailable_message(:instance_unavailable) do
    "Chat is unavailable because this instance is offline. Start or reselect an active instance."
  end

  def chat_unavailable_message(_),
    do: "Chat is unavailable for this instance. Open Interact to run signals and actions."
end
