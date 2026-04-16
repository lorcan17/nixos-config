{ pkgs, ... }:
{
  # Dev tooling for lululemon work — available in PATH via home-manager
  home-manager.users.lorcan = {
    home.packages = with pkgs; [
      # Python — dbt, scripting, data work
      python312
      uv    # fast Python package/project manager (replaces pip/venv/pip-tools)

      # Terraform — Snowflake and Datadog provider work
      terraform

      # SQL linting (Snowflake dialect) — useful in pre-commit and PR reviews
      sqlfluff

      # Local data exploration — SQL on parquet/CSV without Snowflake
      duckdb

      # Quick CSV manipulation
      csvkit

      # GitLab CI/CD debugging — run pipelines locally
      gitlab-runner

      # Render Mermaid diagrams from CLI (architecture docs)
      mermaid-cli
    ];
  };
}
