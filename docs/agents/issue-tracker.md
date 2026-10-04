# Issue tracker: Linear

Issues and specs for this repo live in Linear, accessed through the Linear MCP tools (`mcp__claude_ai_Linear__*`; load them with ToolSearch if deferred).

- **Team**: Matdac6 (key `MAT`, id `71803c02-b562-44be-ab9f-80e26990e5e1`)
- **Project**: SnipNote (https://linear.app/matdac6/project/snipnote-b45cef102e5d). Every issue created for this repo must be assigned to this project.

## Conventions

- **Create an issue**: `save_issue` with `team: "Matdac6"`, `project: "SnipNote"`, `title`, and a markdown `description` (real newlines, no `\n` escapes).
- **Read an issue**: `get_issue` with the identifier (e.g. `MAT-12`), then `list_comments` for the discussion.
- **List issues**: `list_issues` filtered by `project: "SnipNote"`, plus `label` / `state` as needed.
- **Comment on an issue**: `save_comment`.
- **Apply / remove labels**: `save_issue` with the issue `id` and updated `labels`. Labels must already exist (`list_issue_labels`, `create_issue_label`).
- **Close**: `save_issue` with `state: "Done"` (or `"Canceled"` for wontfix), plus a closing comment via `save_comment`.

## Pull requests as a triage surface

**PRs as a request surface: no.** PRs are not part of the triage queue.

## When a skill says "publish to the issue tracker"

Create a Linear issue in the Matdac6 team, SnipNote project.

## When a skill says "fetch the relevant ticket"

Run `get_issue` for the identifier, then `list_comments`.
