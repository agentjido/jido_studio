defmodule JidoStudio.AgentPresenter do
  @moduledoc """
  Behaviour for shaping Agent Detail page data.

  Presenters transform agent module metadata plus optional runtime status
  into a UI view model consumed by `AgentsLive`.
  """

  @type tab :: %{id: atom(), label: String.t()}

  @type badge :: %{
          required(:label) => String.t(),
          optional(:variant) => atom()
        }

  @type section :: %{
          required(:title) => String.t(),
          required(:kind) => :badge | :badges | :text | :kv | :code,
          required(:data) => term(),
          optional(:variant) => atom()
        }

  @type instance_summary :: %{
          required(:title) => String.t(),
          optional(:subtitle) => String.t(),
          optional(:badges) => [badge()],
          optional(:meta) => [{String.t(), String.t()}]
        }

  @type start_field :: %{
          required(:name) => String.t(),
          required(:label) => String.t(),
          required(:type) => :text | :checkbox | :textarea_json,
          optional(:default) => String.t(),
          optional(:placeholder) => String.t(),
          optional(:help) => String.t(),
          optional(:rows) => pos_integer()
        }

  @type chat_config :: %{
          required(:enabled) => boolean(),
          required(:mode) => :ask_sync,
          required(:timeout_ms) => pos_integer(),
          required(:placeholder) => String.t(),
          required(:empty_title) => String.t(),
          required(:empty_description) => String.t(),
          optional(:model_label) => String.t() | nil,
          optional(:streaming_enabled) => boolean(),
          optional(:stream_poll_ms) => pos_integer()
        }

  @type view_model :: %{
          required(:tabs) => [tab()],
          required(:sections_by_tab) => %{optional(atom()) => [section()]},
          required(:system_prompt) => String.t()
        }

  @callback supports?(agent_module :: module(), strategy_module :: module() | nil) :: boolean()

  @callback static(agent_info :: map()) :: view_model()

  @callback runtime(
              agent_info :: map(),
              runtime_status :: Jido.AgentServer.Status.t() | nil,
              opts :: keyword()
            ) :: view_model()

  @callback chat_config(
              agent_info :: map(),
              runtime_status :: Jido.AgentServer.Status.t() | nil,
              opts :: keyword()
            ) :: chat_config()

  @callback instance_summary(
              agent_info :: map(),
              instance_info :: map(),
              runtime_status :: Jido.AgentServer.Status.t() | nil,
              opts :: keyword()
            ) :: instance_summary()

  @callback start_form_schema(agent_info :: map()) :: [start_field()]

  @optional_callbacks chat_config: 3, instance_summary: 4, start_form_schema: 1
end
