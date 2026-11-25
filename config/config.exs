import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: JidoStudio.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/jido_studio",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v",
    types: [
      feat: [header: "Features"],
      fix: [header: "Bug Fixes"],
      perf: [header: "Performance"],
      refactor: [header: "Refactoring"],
      docs: [hidden?: true],
      test: [hidden?: true],
      deps: [hidden?: true],
      chore: [hidden?: true],
      ci: [hidden?: true]
    ]
end
