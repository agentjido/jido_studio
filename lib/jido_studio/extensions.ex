defmodule JidoStudio.Extensions do
  @moduledoc """
  Registry for optional Studio extensions.
  """

  @builtin_extensions [JidoStudio.Extensions.Messaging]

  @type route :: JidoStudio.Extension.route()
  @type nav_section :: JidoStudio.Extension.nav_section()

  @doc """
  Returns built-in extension modules shipped with Studio.
  """
  @spec builtin_extensions() :: [module()]
  def builtin_extensions, do: @builtin_extensions

  @doc """
  Returns extension modules from built-ins, config, and explicit additions.
  """
  @spec modules([module()]) :: [module()]
  def modules(extra_modules \\ []) do
    configured = Application.get_env(:jido_studio, :extension_modules, [])

    @builtin_extensions
    |> Kernel.++(List.wrap(configured))
    |> Kernel.++(List.wrap(extra_modules))
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  @doc """
  Returns extensions that are installed and currently active.
  """
  @spec active_extensions([module()]) :: [module()]
  def active_extensions(extra_modules \\ []) do
    modules(extra_modules)
    |> Enum.filter(&extension_active?/1)
  end

  @doc """
  Returns additional routes contributed by active extensions.
  """
  @spec routes([module()]) :: [route()]
  def routes(extra_modules \\ []) do
    active_extensions(extra_modules)
    |> Enum.flat_map(&safe_routes/1)
  end

  @doc """
  Returns sidebar sections contributed by active extensions.
  """
  @spec nav_sections([module()]) :: [nav_section()]
  def nav_sections(extra_modules \\ []) do
    active_extensions(extra_modules)
    |> Enum.flat_map(&safe_nav_sections/1)
  end

  defp extension_active?(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :installed?, 0),
         true <- module.installed?() do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp safe_routes(module) do
    if function_exported?(module, :routes, 0) do
      module.routes()
      |> List.wrap()
      |> Enum.filter(&valid_route?/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp safe_nav_sections(module) do
    if function_exported?(module, :nav_sections, 0) do
      module.nav_sections()
      |> List.wrap()
      |> Enum.filter(&valid_nav_section?/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp valid_route?(%{path: path, live_view: live_view, action: action})
       when is_binary(path) and is_atom(live_view) and is_atom(action),
       do: true

  defp valid_route?(_), do: false

  defp valid_nav_section?(%{id: id, label: label, items: items})
       when (is_atom(id) or is_binary(id)) and is_binary(label) and is_list(items) do
    Enum.all?(items, &valid_nav_item?/1)
  end

  defp valid_nav_section?(_), do: false

  defp valid_nav_item?(%{path: path, label: label, icon: icon})
       when is_binary(path) and is_binary(label) and is_binary(icon),
       do: true

  defp valid_nav_item?(_), do: false
end
