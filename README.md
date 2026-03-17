# gh-dashboard

[![CI](https://github.com/lambdasistemi/gh-dashboard/actions/workflows/ci.yaml/badge.svg)](https://github.com/lambdasistemi/gh-dashboard/actions/workflows/ci.yaml)

**[Live demo](https://lambdasistemi.github.io/gh-dashboard/)**

Kanban dashboard for GitHub — three-column board (Backlog / WIP / Done) backed by GitHub Projects v2, with integrated agent session management. Runs entirely in the browser as a static page on GitHub Pages.

## How it works

The app maps a single GitHub Project to a Kanban board with three fixed statuses:

| Column | Meaning | Backend state |
|--------|---------|---------------|
| **Backlog** | To be worked on | No worktree, no session |
| **WIP** | Active work | Worktree created, session can be launched |
| **Done** | Completed | Worktree deleted, branch kept until cleanup |

Moving items between columns triggers side effects on the [agent-daemon](https://github.com/lambdasistemi/agent-daemon):

- **→ WIP**: creates a worktree and launches a session
- **← from WIP**: stops any running session, deletes worktree
- Branch and worktree status badges update in real time

## Features

### Kanban board

- Three swipeable columns on mobile (Backlog / WIP / Done)
- Tap to expand issues — shows controls, labels, and full markdown body
- Named action buttons: Launch, Open, Copy, and column transitions (Backlog/WIP/Done)
- Issue number and repo shown per item with badges for branch, worktree, and session state

### Agent integration

- Launch, detach and stop [agent-daemon](https://github.com/lambdasistemi/agent-daemon) sessions from WIP items
- Inline xterm.js terminal for live session interaction
- Branch sync status (synced, ahead, behind, local-only) from daemon API

### Filters

- Repository filter with collapsible org / repo tree
- Label filter with alphabetical list
- Filters apply across all three Kanban columns

### Settings

- Agent server URL configuration
- GitHub API rate limit display
- Dark / light theme toggle
- Import / export settings as JSON
- Reset token and data

### Mobile

- Swipe left/right to navigate between all pages
- Page indicator dots with current column name and item count
- Stacked card layout — no tables on mobile
- Controls inside expanded items, not cluttering the list

## Setup

### 1. GitHub token

Create a [personal access token](https://github.com/settings/tokens/new?scopes=repo,read:project&description=gh-dashboard) with these scopes:

| Scope | Required for |
|-------|-------------|
| `repo` | Issues, PRs, CI checks |
| `read:project` | Project board read/write |

### 2. GitHub Project

The app requires a GitHub Project with exactly three status options:

- **Backlog**
- **WIP**
- **Done**

On first load, select your project in the setup screen. If you don't have one, create it and rename the default statuses (Todo → Backlog, In Progress → WIP, Done stays).

### 3. Agent daemon (optional)

Set the agent server URL in Settings to enable session management, worktree creation, and branch tracking.

## Stack

PureScript · Halogen · GitHub REST & GraphQL API · marked.js · xterm.js · esbuild · Nix

## Development

```bash
nix develop
```

Available commands:

```bash
just build    # compile PureScript
just bundle   # produce dist/index.js
just dev      # watch mode
just format   # format sources with purs-tidy
just lint     # check formatting
just ci       # lint + build + bundle
just serve    # bundle and serve on port 10001
just restart  # bundle, kill old server, serve
just clean    # remove build artifacts
```

Open `dist/index.html` in a browser after bundling.

## License

MIT
