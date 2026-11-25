defmodule JidoStudio.Agents.Introspection do
  @moduledoc false

  alias JidoStudio.AgentInteractions
  alias JidoStudio.Agents.ActionCatalog
  alias JidoStudio.Agents.SignalCatalog
  alias JidoStudio.Chat.Runtime, as: ChatRuntime

  @type introspection_model :: %{
          signals: [map()],
          actions: [map()],
          warnings: [String.t()],
          chat_supported?: boolean(),
          runner_supported?: boolean(),
          dispatch_available?: boolean(),
          primary_default_tab: :chat | :interact
        }

  @spec build(module() | nil, map() | pid() | nil, keyword()) :: introspection_model()
  def build(agent_module, instance \\ nil, opts \\ []) do
    signal_model = SignalCatalog.build(agent_module, instance, opts)
    action_model = ActionCatalog.build(agent_module, signal_model.signals, opts)

    chat_supported? = safe_chat_supported?(agent_module)

    runner_supported? =
      AgentInteractions.enabled?() and
        (signal_model.signals != [] or action_model.actions != [])

    dispatch_available? = is_pid(extract_pid(instance))

    %{
      signals: signal_model.signals,
      actions: action_model.actions,
      warnings: Enum.uniq(signal_model.warnings ++ action_model.warnings),
      chat_supported?: chat_supported?,
      runner_supported?: runner_supported?,
      dispatch_available?: dispatch_available?,
      primary_default_tab:
        primary_tab(chat_supported?, runner_supported?, AgentInteractions.default_tab())
    }
  end

  defp primary_tab(chat_supported?, runner_supported?, :chat) do
    if chat_supported?, do: :chat, else: if(runner_supported?, do: :interact, else: :chat)
  end

  defp primary_tab(chat_supported?, runner_supported?, :interact) do
    if runner_supported?, do: :interact, else: if(chat_supported?, do: :chat, else: :chat)
  end

  defp primary_tab(chat_supported?, runner_supported?, :auto) do
    cond do
      chat_supported? -> :chat
      runner_supported? -> :interact
      true -> :chat
    end
  end

  defp primary_tab(chat_supported?, runner_supported?, _),
    do: primary_tab(chat_supported?, runner_supported?, :auto)

  defp safe_chat_supported?(agent_module) when is_atom(agent_module) do
    ChatRuntime.supports?(agent_module)
  rescue
    _ -> false
  end

  defp safe_chat_supported?(_), do: false

  defp extract_pid(%{pid: pid}) when is_pid(pid), do: pid
  defp extract_pid(%{active_instance_pid: pid}) when is_pid(pid), do: pid
  defp extract_pid(pid) when is_pid(pid), do: pid
  defp extract_pid(_), do: nil
end
