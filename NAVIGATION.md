# gh-dashboard

Kanban dashboard for GitHub — three-column board (Backlog / WIP / Done) backed by GitHub Projects v2, with integrated agent session management.

## Architecture

```
User interaction -> Action emitted -> Main.handleAction dispatches
                                           |
                 +-----------+-------------+-----------+
                 |           |             |           |
            Action.Repos  Action.Projects  Action.Agent  (inline)
                 |           |             |
            GitHub.Rest  GitHub.GraphQL  Fetch (agent HTTP)
                 |
            FFI.Cache (IndexedDB ETag caching)
```

### Module layout

```
src/
  App/
    Main.purs              -- Entry point, component, action dispatcher
    Storage.purs           -- localStorage persistence
    Refresh.purs           -- Repo/PR refresh logic
    Action/
      Common.purs          -- Shared helpers (Dispatch, persistView, toggleSet)
      Repos.purs           -- Repo page handlers
      Projects.purs        -- Project/Kanban handlers + agent side effects
      Agent.purs           -- Agent session/terminal handlers
    View.purs              -- Top-level render (toolbar, settings, page indicator)
    View/
      Types.purs           -- Action, State, Toast types
      Kanban.purs          -- Three-column Kanban view + filters + project setup
      Projects.purs        -- Item row rendering (shared by Kanban)
      Agents.purs          -- Legacy agents view
      Widgets.purs         -- Named buttons (Launch, Open, Copy, etc.)
      Issues.purs          -- Issue section renderer
      PRs.purs             -- PR section renderer
      Workflows.purs       -- Workflow section renderer
      RepoTable.purs       -- Repo table renderer
      Detail.purs          -- Detail panel compositor
  Lib/
    Types.purs             -- Domain types (Repo, Issue, Project, Page, etc.)
    GitHub.purs            -- API facade re-export
    GitHub/
      Rest.purs            -- REST v3 with ETag caching
      GraphQL.purs         -- GraphQL for Projects v2
    UI/
      Helpers.purs         -- Shared renderers (markdown, terminal, dates)
      Widgets.purs         -- Reusable widgets (settingsRow, labelSelector)
    Util/
      Repo.purs            -- Pure repo helpers (filter, parse, reorder)
    FFI/
      Cache.purs + .js     -- IndexedDB cache
      Storage.purs + .js   -- Token encryption, export/import
      Terminal.purs + .js  -- xterm.js WebSocket terminals
      Swipe.purs + .js     -- Touch swipe detection
      Clipboard.purs + .js -- navigator.clipboard
      Dialog.purs + .js    -- window.confirm
      Theme.purs + .js     -- Dark/light theme toggle
```

## Kanban board

The app presents a single GitHub Project as three columns:

| Page | Status | Description |
|------|--------|-------------|
| **Backlog** | `Backlog` | Items to be worked on |
| **WIP** | `WIP` | Active work with worktree and optional session |
| **Done** | `Done` | Completed items, branch kept until cleanup |

### Column transitions

Moving items between columns triggers agent-daemon side effects:

- **Any → WIP**: POST `/sessions` — creates worktree + tmux session
- **WIP → Any**: DELETE `/sessions/:sid` — stops session, deletes worktree
- Status update via GitHub GraphQL `updateProjectV2ItemFieldValue`

### Item rendering

Each item shows:
- **Header row**: issue number (left) + repo name (right)
- **Title row**: badges (branch, worktree, session) + title
- **Expanded**: controls (Launch, Open, Copy, move buttons) + labels + markdown body

### Badges

| Badge | Meaning | Source |
|-------|---------|--------|
| Branch (⎇) | Local `feat/issue-N` branch exists | `GET /branches` |
| Worktree (🌳) | Git worktree exists | `GET /worktrees` |
| Session (◉) | Agent session running | `GET /sessions` |

Badges are hidden contextually: no session controls outside WIP, no worktree badge in Done.

## Agent daemon integration

The dashboard communicates with [agent-daemon](https://github.com/lambdasistemi/agent-daemon) for:

| Endpoint | Purpose |
|----------|---------|
| `GET /sessions` | List active sessions |
| `POST /sessions` | Launch session for repo/issue |
| `DELETE /sessions/:sid` | Stop session + cleanup |
| `GET /worktrees` | List worktree directories |
| `GET /branches` | List local branches with sync status |
| `DELETE /branches/:repo/:branch` | Delete local + remote branch |

## Mobile UX

- **Swipe** left/right to navigate: Backlog ↔ WIP ↔ Done ↔ Filters ↔ Settings
- **Page indicator** dots with column name and item count
- **Stacked card layout** — table cells become vertical blocks
- **Tap to expand** — controls appear inside the expanded body
- Kanban tabs hidden on mobile (swipe replaces them)

## Filters pane (⫶)

- **Repositories**: collapsible org → repo tree with counts
- **Labels**: alphabetical list, collapsible

Filters apply across all three Kanban columns.

## Settings pane (⚙)

| Setting | Description |
|---------|-------------|
| Agent | Agent daemon server URL |
| GitHub API | Rate limit remaining/total |
| Theme | Dark / light toggle |
| Data | Export, Import, Reset token, Reset all |
| About | Source code link |

## Persistence

| localStorage key | Content |
|-----------------|---------|
| `gh-dashboard-token` | AES-256-GCM encrypted GitHub PAT |
| `gh-dashboard-crypto-key` | JWK AES key for token encryption |
| `gh-dashboard-repos` | Ordered repo name array |
| `gh-dashboard-view` | View state (current page, expanded items, filters, theme) |
| `gh-dashboard-agent-server` | Agent daemon URL |
| `gh-dashboard-kanban-project` | Selected GitHub Project node ID |

## Key design decisions

- **Dispatch callback**: handler modules receive a `Dispatch` function to avoid circular imports
- **Optimistic updates**: status changes apply immediately, roll back on API error
- **ETag caching**: REST calls use IndexedDB for conditional requests (304 = cached)
- **Token encryption**: AES-256-GCM at rest, PBKDF2 passphrase for export
- **No columns on mobile**: same stacked card layout everywhere
- **Controls inside expanded body**: keeps the list clean, tap to act
