defmodule JidoStudio.AboutLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  @default_links [
    %{label: "Agent Jido", url: "https://agentjido.xyz"},
    %{label: "LLMDB", url: "https://llmdb.xyz"},
    %{label: "GitHub", url: "https://github.com/sagents-ai/jido_studio"},
    %{label: "Community", url: "https://github.com/sagents-ai/jido/discussions"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    branding = branding_config()

    socket =
      socket
      |> assign(:page_title, "About")
      |> assign(:tagline, Keyword.get(branding, :about_tagline, default_tagline()))
      |> assign(
        :about_links,
        normalize_links(Keyword.get(branding, :about_links, @default_links))
      )
      |> assign(:docs_url, normalize_url(Keyword.get(branding, :docs_url)))
      |> assign(:support_email, normalize_optional_string(Keyword.get(branding, :support_email)))
      |> assign(:studio_version, JidoStudio.version())
      |> assign(:jido_version, jido_version())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="About" subtitle="What Jido Studio is and where to go next" />

      <.card>
        <h2 class="text-sm font-semibold text-js-text">Jido Studio</h2>
        <p class="mt-2 text-sm text-js-text-muted">{@tagline}</p>
        <p class="mt-3 text-xs text-js-text-subtle">
          Jido Studio gives you one place to observe Agents, understand runtime behavior, and troubleshoot issues without losing access to deep technical tools.
        </p>
      </.card>

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-4">
        <.card>
          <h2 class="text-sm font-semibold text-js-text">Community and Resources</h2>
          <div class="mt-3 space-y-2">
            <a
              :for={link <- @about_links}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              {link.label}
            </a>
            <a
              :if={@docs_url}
              href={@docs_url}
              target="_blank"
              rel="noopener noreferrer"
              class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Documentation
            </a>
          </div>
        </.card>

        <.card>
          <h2 class="text-sm font-semibold text-js-text">Runtime Info</h2>
          <div class="mt-3 space-y-2 text-xs text-js-text-muted">
            <div class="flex items-center justify-between gap-3">
              <span>Jido Studio</span>
              <span class="font-mono">{@studio_version}</span>
            </div>
            <div class="flex items-center justify-between gap-3">
              <span>Jido</span>
              <span class="font-mono">{@jido_version}</span>
            </div>
            <div :if={@support_email} class="pt-2 border-t border-js-border">
              Support: <span class="font-mono">{@support_email}</span>
            </div>
          </div>
        </.card>
      </div>
    </div>
    """
  end

  defp branding_config do
    Application.get_env(:jido_studio, :branding, [])
  end

  defp normalize_links(links) when is_list(links) do
    links
    |> Enum.flat_map(fn
      %{label: label, url: url} -> normalize_link(label, url)
      %{"label" => label, "url" => url} -> normalize_link(label, url)
      _ -> []
    end)
    |> case do
      [] -> @default_links
      values -> values
    end
  end

  defp normalize_links(_), do: @default_links

  defp normalize_link(label, url) do
    with label when is_binary(label) and label != "" <- normalize_optional_string(label),
         url when is_binary(url) and url != "" <- normalize_url(url) do
      [%{label: label, url: url}]
    else
      _ -> []
    end
  end

  defp normalize_url(url) when is_binary(url) do
    url = String.trim(url)

    if url == "" do
      nil
    else
      url
    end
  end

  defp normalize_url(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_string(_), do: nil

  defp default_tagline do
    "Observe, understand, and guide your Agents from one place."
  end

  defp jido_version do
    case Application.spec(:jido, :vsn) do
      nil -> "not loaded"
      vsn -> List.to_string(vsn)
    end
  end
end
