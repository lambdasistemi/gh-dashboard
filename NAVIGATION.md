# NAVIGATION.md

Codebase map for [gh-dashboard](https://github.com/lambdasistemi/gh-dashboard).
All links point to commit [`4b69256`](https://github.com/lambdasistemi/gh-dashboard/tree/4b69256).

---

## Architecture Overview

A single-page PureScript + Halogen app that renders a personal GitHub dashboard with two pages: **Repos** (REST API) and **Projects** (GraphQL API). An optional agent server provides Claude Code sessions attached to issues via WebSocket terminals.

```
User clicks -> Action emitted -> Main.handleAction dispatches
                                      |
              +----------+------------+----------+
              |          |            |          |
         Action.Repos  Action.Projects  Action.Agent  (inline one-liners)
              |          |            |
         GitHub.Rest  GitHub.GraphQL  Fetch (agent HTTP)
              |
         FFI.Cache (IndexedDB ETag caching)
```

Key design decisions:
- **Dispatch callback** -- handler modules receive a `Dispatch` function instead of importing each other, avoiding circular dependencies.
- **Optimistic updates** -- project status changes, renames, and deletes modify state before the API call, then roll back on error.
- **Lazy loading** -- detail sections (issues, PRs, workflows) fetch data only when first expanded.
- **Single expanded repo** -- only one repo can be expanded at a time; switching clears the previous detail.
- **ETag-based caching** -- all REST API calls go through IndexedDB; 304 responses serve cached data instantly.
- **Token encryption** -- GitHub PAT is encrypted at rest with AES-256-GCM, and export/import uses passphrase-derived keys.
- **Toast notifications** -- non-blocking feedback with auto-dismiss after 4 seconds.

---

## Domain Types

[`src/Types.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L1-L299) defines all domain newtypes and their `DecodeJson` instances.

| Type | Purpose | Key fields |
|------|---------|------------|
| [`Repo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L40-L52) | A GitHub repository | `fullName`, `ownerLogin`, `defaultBranch`, `openIssuesCount` |
| [`Issue`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L86-L95) | An open issue (excludes PRs) | `number`, `title`, `labels`, `assignees`, `body` |
| [`PullRequest`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L122-L133) | An open PR | `number`, `title`, `draft`, `headSha`, `labels` |
| [`CheckRun`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L165-L170) | A CI check run | `name`, `status`, `conclusion` |
| [`WorkflowRun`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L188-L197) | A workflow run on the default branch | `runId`, `name`, `headSha`, `displayTitle` |
| [`WorkflowJob`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L230-L235) | A single job within a workflow run | `name`, `status`, `conclusion` |
| [`Project`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L258-L263) | A Projects v2 board | `id`, `title`, `url`, `itemCount` |
| [`ProjectItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L266-L277) | An item on a project board | `itemId`, `draftId`, `status`, `itemType`, `repoName`, `labels` |
| [`RepoDetail`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L287-L298) | Cached detail for an expanded repo | `issues`, `pullRequests`, `prChecks`, `workflowRuns`, `workflowJobs` |
| [`Page`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L253-L255) | Active top-level page | `ReposPage` or `ProjectsPage` |
| [`StatusField`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L280-L284) | Status field metadata for a project | `fieldId`, `options` array of `{optionId, name}` |

Supporting type aliases: [`Label`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L30-L32), [`Assignee`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L35-L37), [`CommitPR`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Types.purs#L224-L227).

---

## GitHub API Client

The API layer is split into REST and GraphQL, re-exported from a single facade module.

### Facade

[`src/GitHub.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub.purs#L1-L44) re-exports everything from `GitHub.Rest` and `GitHub.GraphQL`.

### REST (v3) with IndexedDB Caching

[`src/GitHub/Rest.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L1-L519)

Core transport:

| Function | Purpose |
|----------|---------|
| [`ghFetch`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L93-L154) | Authenticated GET with ETag-based IndexedDB caching. On each request: (1) look up cached ETag, (2) send `If-None-Match`, (3) on 304 return cached body, (4) on 200 store new ETag + body. Extracts rate-limit headers and `Link: rel="next"`. |
| [`parseLinkNext`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L163-L195) | Extracts the next-page URL from RFC 5988 Link headers. |
| [`fetchAllPages`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L202-L233) | Follows pagination to accumulate all items into a single array. |

Domain fetch functions:

| Function | Endpoint |
|----------|----------|
| [`fetchUserRepos`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L240-L258) | `GET /user/repos?affiliation=owner,collaborator` |
| [`fetchRepoIssues`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L278-L297) | `GET /repos/:full/issues` (filters out PRs via `RawIssue` wrapper) |
| [`fetchIssue`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L300-L315) | `GET /repos/:full/issues/:n` |
| [`fetchRepo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L318-L330) | `GET /repos/:full` |
| [`fetchRepoPRs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L333-L343) | `GET /repos/:full/pulls?state=open` |
| [`fetchPR`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L346-L361) | `GET /repos/:full/pulls/:n` |
| [`fetchCheckRuns`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L364-L385) | `GET /repos/:full/commits/:sha/check-runs` |
| [`fetchCommitStatuses`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L393-L441) | `GET /repos/:full/commits/:sha/statuses` -- converts legacy statuses into `CheckRun` for uniform rendering |
| [`fetchWorkflowRuns`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L445-L467) | `GET /repos/:full/actions/runs?branch=...` |
| [`fetchWorkflowJobs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L470-L489) | `GET /repos/:full/actions/runs/:id/jobs` |
| [`fetchCommitPRs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/Rest.purs#L492-L519) | `GET /repos/:full/commits/:sha/pulls` -- returns the first associated PR |

### GraphQL (Projects v2)

[`src/GitHub/GraphQL.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L1-L640)

Core transport:

| Function | Purpose |
|----------|---------|
| [`ghGraphQL`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L76-L107) | POST `{query, variables}` to `/graphql`. Extracts GraphQL-level errors. |
| [`ghMutation`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L262-L268) | Wrapper for mutations that return no useful data. |
| [`extractGraphQLErrors`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L111-L129) | Parses the `errors` array from a GraphQL response. |

Queries and mutations:

| Function | GraphQL operation |
|----------|-------------------|
| [`fetchUserProjects`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L199-L208) | `viewer.projectsV2` -- light metadata only |
| [`fetchProjectItems`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L215-L252) | Paginated items for a project, plus status field metadata |
| [`updateItemStatus`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L271-L302) | `updateProjectV2ItemFieldValue` |
| [`addDraftItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L305-L325) | `addProjectV2DraftIssue` |
| [`updateDraftItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L328-L348) | `updateProjectV2DraftIssue` |
| [`renameProject`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L351-L371) | `updateProjectV2` |
| [`deleteProjectItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L374-L394) | `deleteProjectV2Item` |

Response navigation helpers ([L400-L640](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L400-L640)):

| Function | Purpose |
|----------|---------|
| [`jsonField`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L470-L474) | Navigate into a JSON object field (combines `toObject` + `.:` into one step) |
| [`optField`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/GitHub/GraphQL.purs#L478-L488) | Read an optional value from a JSON object, returning `Maybe` on missing/error |
| `navigateProjects` | Walk `data.viewer.projectsV2.nodes` |
| `navigateProjectItems` | Walk `data.node.items`, extract status field metadata |
| `parseProjectItem` | Parse a single item node including fieldValues |
| `extractFieldValue` | Extract single-select field value by field name |
| `extractLabels` | Extract labels from field value nodes |
| `parseStatusField` | Find the "Status" field and its options |

---

## Application State and Initialization

### State

[`src/View/Types.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Types.purs#L89-L137) defines the full `State` record.

| Field group | Fields | Purpose |
|-------------|--------|---------|
| Auth | `token`, `hasToken` | GitHub PAT (decrypted, in memory only) |
| Repos page | `repos`, `repoList`, `expanded`, `details`, `detailLoading`, `loading` | Repo list, which one is expanded, cached detail |
| Feedback | `error`, `info`, `rateLimit` | Error messages, rate-limit display |
| Filters | `filterText`, `issueLabelFilters`, `prLabelFilters`, `workflowStatusFilters`, `projectRepoFilters`, `sessionFilters` | Various filter Sets |
| UI toggles | `expandedItems`, `hiddenItems`, `showAddRepo`, `addRepoInput`, `darkTheme`, `dragging` | Expand/collapse, hidden items, theme |
| Section loading | `issuesLoading`, `prsLoading`, `workflowsLoading`, `projectsLoading`, `projectItemsLoading` | Spinner flags |
| Projects page | `currentPage`, `projects`, `expandedProject`, `projectItems`, `projectStatusFields`, `newItemTitle`, `editingItem`, `editItemTitle`, `editingProject`, `editProjectTitle` | Projects v2 state |
| Agent | `agentServer`, `launchedItems`, `terminalKeys`, `terminalUrls`, `agentSessions`, `agentWorktrees`, `sessionFilters` | Agent daemon integration + worktree indicators |
| Toasts | `toasts`, `nextToastId` | Toast notification queue with auto-dismiss |

### Toast System

[`src/View/Types.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Types.purs#L23-L30)

| Type | Definition |
|------|------------|
| `ToastLevel` | `ToastInfo \| ToastError` |
| `Toast` | `{ id :: Int, message :: String, level :: ToastLevel }` |

Toasts are appended by `ShowToast`, auto-dismissed after 4 seconds via `delay` in [`Main.handleAction`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Main.purs#L458-L478), and manually dismissable via `DismissToast`. Rendered as a fixed container in [`View.renderToasts`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L281-L310).

### Initialization

[`Main.purs` Initialize handler](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Main.purs#L200-L236) runs on mount:

1. Load encrypted token from localStorage via `FFI.Storage.loadTokenEncrypted` (decrypts AES-256-GCM).
2. Load repo list, agent server URL, and view state from localStorage.
3. Apply the persisted theme to `<body>`.
4. Restore all persisted view fields into state.
5. If a token exists, refresh agent sessions then either fetch repos (ReposPage) or projects + items (ProjectsPage).

[`initialState`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Main.purs#L122-L170) sets every field to its empty/default value.

---

## Action Dispatch

[`src/View/Types.purs` Action](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Types.purs#L33-L87) is a flat sum type with 54 constructors. The dispatcher in [`Main.handleAction`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Main.purs#L190-L478) is a single `case _ of` that routes each constructor:

- **Initialization and auth** (L200-L253): `Initialize`, `SetToken`, `SubmitToken`
- **Repo actions** (L259-L288): delegated to `Action.Repos`
- **Inline one-liners** (L294-L397): `SetFilter`, `ToggleAddRepo`, `CopyText`, filter toggles, `ToggleTheme`, `ExportStorage`, `ImportStorage`, `ResetToken`, `ResetAll`, `SwitchPage`
- **Project actions** (L403-L433): delegated to `Action.Projects`
- **Agent actions** (L439-L452): delegated to `Action.Agent`
- **Toast actions** (L458-L478): `ShowToast`, `DismissToast`

The dispatcher passes itself as a `Dispatch` callback to handler modules that need cross-module action calls.

### Action Constructors

| Constructor | Parameters | Handler module |
|-------------|------------|----------------|
| `Initialize` | -- | Main (inline) |
| `SetToken` | `String` | Main (inline) |
| `SubmitToken` | -- | Main (inline) |
| `RefreshRepo` | `String` (fullName) | Action.Repos |
| `RefreshIssues` | -- | Action.Repos |
| `RefreshIssue` | `Int` (number) | Action.Repos |
| `RefreshPRs` | -- | Action.Repos |
| `RefreshPR` | `Int` (number) | Action.Repos |
| `RefreshWorkflows` | -- | Action.Repos |
| `WorkflowPrevSha` / `WorkflowNextSha` | -- | Action.Repos |
| `ToggleExpand` | `String` (fullName) | Action.Repos |
| `ToggleItem` | `String` (key) | Action.Repos |
| `DragStart` / `DragDrop` | `String` (fullName) | Action.Repos |
| `SubmitAddRepo` | -- | Action.Repos |
| `RemoveRepo` | `String` (fullName) | Action.Repos |
| `HideItem` | `String` (url) | Action.Repos |
| `SetFilter` | `String` | Main (inline) |
| `ToggleAddRepo` | -- | Main (inline) |
| `SetAddRepoInput` | `String` | Main (inline) |
| `CopyText` | `String` | Main (inline) |
| `ToggleIssueLabelFilter` | `String` | Main (inline) |
| `TogglePRLabelFilter` | `String` | Main (inline) |
| `ToggleWorkflowStatusFilter` | `String` | Main (inline) |
| `ToggleTheme` | -- | Main (inline) |
| `ExportStorage` / `ImportStorage` | -- | Main (inline) |
| `ResetToken` | -- | Main (inline) |
| `ResetAll` | -- | Main (inline) |
| `SwitchPage` | `Page` | Main (inline) |
| `RefreshProjects` | -- | Action.Projects |
| `ExpandProject` | `String` (projectId) | Action.Projects |
| `RefreshProjectItems` | `String` (projectId) | Action.Projects |
| `RefreshProjectItem` | `String String Int` | Action.Projects |
| `ToggleProjectRepoFilter` | `String` | Action.Projects |
| `SetItemStatus` | `String String String` | Action.Projects |
| `SetNewItemTitle` | `String` | Action.Projects |
| `SubmitNewItem` | `String` (projectId) | Action.Projects |
| `StartEditItem` | `String String` | Action.Projects |
| `SetEditItemTitle` | `String` | Action.Projects |
| `SubmitEditItem` | `String String String` | Action.Projects |
| `DeleteItem` | `String String` | Action.Projects |
| `StartRenameProject` | `String String` | Action.Projects |
| `SetRenameProjectTitle` | `String` | Action.Projects |
| `SubmitRenameProject` | `String String` | Action.Projects |
| `LaunchAgent` | `String String Int` | Action.Agent |
| `DetachAgent` | `String Int` | Action.Agent |
| `StopAgent` | `String Int` | Action.Agent |
| `SetAgentServer` | `String` | Action.Agent |
| `RefreshAgentSessions` | -- | Action.Agent |
| `ToggleSessionFilter` | `String` | Action.Agent |
| `ShowToast` | `String ToastLevel` | Main (inline) |
| `DismissToast` | `Int` | Main (inline) |

---

## Repo Action Handlers

[`src/Action/Repos.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L1-L584)

### Data fetching

| Handler | Behavior |
|---------|----------|
| [`handleRefreshRepo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L104-L114) | Re-fetch and upsert a single repo |
| [`handleRefreshIssues`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L116-L135) | Fetch open issues for the expanded repo, guarded by `guardExpanded` |
| [`handleRefreshIssue`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L137-L158) | Refresh a single issue in-place via `updateDetail` |
| [`handleRefreshPRs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L160-L223) | Fetch open PRs, then check-runs + commit statuses per PR (skips hidden PRs) |
| [`handleRefreshPR`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L225-L232) | Re-fetch a single PR and its checks via `Refresh.refreshSinglePR` |
| [`handleRefreshWorkflows`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L234-L270) | Fetch workflow runs, extract unique SHAs, load jobs for the first SHA |
| [`handleWorkflowPrevSha` / `handleWorkflowNextSha`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L272-L316) | Navigate between SHAs in the workflow viewer |
| [`loadWorkflowShaDetails`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L512-L583) | Load jobs and PR info for the currently selected SHA |
| [`extractShas`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L500-L508) | Deduplicate SHAs preserving order |

### UI interactions

| Handler | Behavior |
|---------|----------|
| [`handleToggleExpand`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L318-L341) | Expand/collapse a repo row. Clears details when switching repos. |
| [`handleToggleItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L343-L398) | Expand/collapse a detail section. Detaches terminals on collapse. Auto-fetches on first open of `section-issues`, `section-prs`, `section-workflows`. |
| [`handleDragStart` / `handleDragDrop`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L400-L422) | Drag-and-drop repo reordering |
| [`handleSubmitAddRepo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L424-L462) | Add a repo by URL or `owner/repo` name (deduplicates) |
| [`handleRemoveRepo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L464-L489) | Confirm and remove a repo from the list |
| [`handleHideItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Repos.purs#L491-L497) | Toggle hide/unhide for an issue or PR |

---

## Project Action Handlers

[`src/Action/Projects.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L1-L453)

| Handler | Behavior |
|---------|----------|
| [`handleRefreshProjects`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L81-L100) | Fetch project list via GraphQL, refresh agent sessions on success |
| [`handleExpandProject`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L102-L125) | Toggle expand; lazy-loads items on first open |
| [`handleRefreshProjectItems`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L127-L165) | Paginated fetch of items + status field metadata |
| [`handleRefreshProjectItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L167-L204) | Re-fetch a single issue's title/body from REST |
| [`handleSetItemStatus`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L216-L270) | **Optimistic** status change via `updateItemStatus` mutation |
| [`handleSubmitNewItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L277-L293) | Create a draft issue then refresh items |
| [`handleSubmitEditItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L311-L349) | **Optimistic** rename of a draft issue |
| [`handleDeleteItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L351-L383) | Confirm, **optimistic** remove, then API delete |
| [`handleSubmitRenameProject`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L401-L427) | **Optimistic** project rename |
| [`friendlyProjectError`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Projects.purs#L432-L453) | Rewrites `insufficient_scopes` errors into a user-friendly hint about `read:project` |

---

## Agent / Terminal Handlers

[`src/Action/Agent.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L1-L370)

The agent integration connects to an external daemon that runs Claude Code sessions against GitHub issues. Sessions are identified by `"owner/repo#issue"` keys.

| Handler | Behavior |
|---------|----------|
| [`handleLaunchAgent`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L81-L181) | POST `/sessions` to create a session, derive WebSocket URL, expand the item, attach xterm.js terminal. Shows toast on success/error. |
| [`handleDetachAgent`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L183-L202) | Destroy the terminal widget without stopping the remote session. Shows toast. |
| [`handleStopAgent`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L204-L257) | Confirm, destroy terminal, DELETE `/sessions/:sid`. Shows toast on success/error. |
| [`handleSetAgentServer`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L259-L263) | Save agent server URL to state and localStorage |
| [`handleRefreshAgentSessions`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L265-L316) | GET `/sessions` for session states, then GET `/worktrees` for worktree presence (independent fetch). Updates `agentSessions` and `agentWorktrees`. |
| [`handleToggleSessionFilter`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L318-L324) | Toggle "Worktree" / "Running" filter |
| [`reattachTerminals`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L329-L341) | Re-opens xterm instances after Halogen re-renders may have destroyed container divs |
| [`parseSession`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L345-L358) | Parse a session JSON object into `(key, state)` tuple |
| [`parseWorktreeKey`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Agent.purs#L361-L369) | Parse a worktree JSON object into a session key |

---

## Shared Action Helpers

[`src/Action/Common.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L1-L142)

| Export | Purpose |
|--------|---------|
| [`Dispatch`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L50-L51) | Type alias for the cross-module action callback |
| [`HalogenAction`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L54-L55) | Shorthand for the Halogen action monad |
| [`toggleSet`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L61-L64) | Insert-or-remove from a Set. Used by every filter toggle. |
| [`persistView`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L71-L87) | Save current view state to localStorage. Called after most user-facing state changes. |
| [`updateDetail`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L102-L112) | Modify the current `RepoDetail`, creating an empty one if none exists. Eliminates repeated Nothing/Just case splits. |
| [`guardExpanded`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L118-L125) | Run an action only if the given repo is still expanded (guards against stale async results) |
| [`emptyDetail`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L129-L141) | Blank `RepoDetail` record |
| [`termElementId`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Action/Common.purs#L92-L96) | Converts `"owner/repo#42"` to a safe DOM ID `"term-owner-repo-42"` |

---

## Refresh Logic

[`src/Refresh.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Refresh.purs#L1-L135)

| Function | Purpose |
|----------|---------|
| [`doRefresh`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Refresh.purs#L30-L72) | If `repoList` is empty, seeds from API (top 25 repos). Otherwise re-fetches each repo individually and reorders. |
| [`refreshSinglePR`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Refresh.purs#L75-L135) | Re-fetch a PR + its check-runs and commit statuses, merge into existing detail state |

---

## Repo Utilities

[`src/RepoUtils.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L1-L90) -- pure helpers for repo list manipulation.

| Function | Purpose |
|----------|---------|
| [`applyFilter`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L21-L34) | Filter repos by name or description (case-insensitive) |
| [`parseRepoName`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L37-L53) | Extract `owner/repo` from a GitHub URL or plain name |
| [`upsertRepo`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L56-L68) | Insert or update a repo in the array |
| [`orderRepos`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L71-L77) | Reorder repos to match the stored list |
| [`moveItem`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/RepoUtils.purs#L80-L89) | Move an item before another (used by drag-and-drop) |

---

## View Layer

### Top-level View

[`src/View.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L1-L332)

| Function | Purpose |
|----------|---------|
| [`renderTokenForm`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L22-L88) | Token input form with "Getting started" instructions |
| [`renderDashboard`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L91-L151) | Main dashboard: toast container, toolbar, add-repo bar, error, page content |
| [`renderToolbar`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L154-L274) | Tab bar (Repos/Projects), filter input, agent server input, theme toggle, export/import, reset token, reset all buttons |
| [`renderToasts`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L281-L310) | Fixed bottom-right toast container, each toast with dismiss button |
| [`renderRateLimit`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View.purs#L313-L332) | Rate limit `remaining/limit` display (warns when < 100) |

### View Types

[`src/View/Types.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Types.purs#L1-L138) defines `Action` (54 constructors), `State` (48 fields), `Toast`, and `ToastLevel`. These are shared across all view sub-modules.

### Repo Table

[`src/View/RepoTable.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/RepoTable.purs#L1-L181)

Renders the repo list as a table with columns: drag handle, actions, name, description, language, visibility, issues, updated date. Each row is clickable (expand/collapse) and draggable (reorder). Expanded repos show the detail panel below.

Helper renderers: `renderLangBadge`, `renderVisBadge`, `renderCountBadge`.

### Detail Panel

[`src/View/Detail.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Detail.purs#L1-L53) -- composes the three detail sections (workflows, issues, PRs) into a single panel below the expanded repo row.

### Issues Section

[`src/View/Issues.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Issues.purs#L1-L297)

- `renderIssuesSection`: Collapsible section with label filter, visible/hidden partitions
- `renderIssueRow`: Single issue row with agent badges (worktree indicator, running badge), agent launch/detach/stop buttons, expandable body or terminal

### PRs Section

[`src/View/PRs.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/PRs.purs#L1-L438)

- `renderPRsSection`: Collapsible section with label + CI status filter, visible/hidden partitions
- `renderPRRow`: Single PR row with draft tag, CI status badge, expandable body + failed checks side-by-side
- `combineCheckRuns`: Derives combined CI status from check runs (pending/failure/cancelled/success/mixed)
- `renderCheckRun`: Single check run with status badge and link

### Workflows Section

[`src/View/Workflows.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Workflows.purs#L1-L351)

- `renderWorkflowsSection`: Collapsible section with SHA navigation, status filter, workflow table
- `renderShaNav`: Prev/next SHA navigation bar with commit link and associated PR
- `renderWorkflowRow`: Single workflow run with failed job sub-rows

### Projects View

[`src/View/Projects.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Projects.purs#L1-L865)

- `renderProjects`: Expandable project table
- `renderProjectRow`: Project row with rename inline edit
- `renderProjectDetail`: Detail panel with new-item form, session filter, repo filter, status-grouped items
- `renderSessionFilter`: Filter buttons for Worktree and Running session states
- `applySessionFilter`: Filters items by worktree/running presence via `agentWorktrees` and `agentSessions`
- `renderRepoFilter`: Collapsible org-grouped repo filter tree (built by `groupByOrg`)
- `groupByStatus`: Groups items by status column (Backlog, Todo, In Progress, Done, Stale, (no status))
- `renderStatusSection`: Collapsible status column with item rows
- `renderItemRow`: Project item row with status selector, agent badges (worktree, running), inline edit, expandable body/terminal

### Detail Widgets

[`src/View/DetailWidgets.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/DetailWidgets.purs#L1-L160) -- reusable buttons and selectors shared across Issues, PRs, and Projects views.

| Widget | Purpose |
|--------|---------|
| `refreshButton` | Refresh icon button |
| `copyButton` | Copy-to-clipboard button |
| `hideButton` | Hide/unhide toggle |
| `launchButton` | Launch/detach/stop agent buttons (context-sensitive) |
| `collectLabels` | Collect unique label names with counts from items |
| `renderLabelSelector` | Multi-select label/status filter bar |

### View Helpers

[`src/View/Helpers.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Helpers.purs#L1-L195) + [`src/View/Helpers.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Helpers.js#L1-L7)

| Helper | Purpose |
|--------|---------|
| `renderMarkdownRow` | Table row with markdown-rendered body (uses `marked.js` via FFI) |
| `renderTerminalRow` | Table row with terminal container div + resize handle |
| `termElementId` | Convert `owner/repo#42` to safe DOM ID |
| `linkButton` | "Open on GitHub" link |
| `detailHead` | Standard column headers for detail tables |
| `renderAssignees` | Comma-separated assignee links |
| `renderAuthor` | Author link to GitHub profile |
| `renderLabels` | Label tag spans |
| `formatDate` | ISO date to `YYYY-MM-DD` |
| `formatDateTime` | ISO date to `YYYY-MM-DD HH:MM` |
| `parseMarkdownImpl` | Foreign import to `marked.parse()` |

---

## Persistence

[`src/Storage.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Storage.purs#L1-L267)

### localStorage Keys

| Key | Type | Purpose |
|-----|------|---------|
| `gh-dashboard-token` | `String` | AES-256-GCM encrypted token (base64 of iv12 + ciphertext) |
| `gh-dashboard-crypto-key` | `String` | JWK-encoded AES-256-GCM key for at-rest token encryption |
| `gh-dashboard-repos` | `JSON Array<String>` | Ordered repo full names |
| `gh-dashboard-view` | `JSON Object` | Full view state (see below) |
| `gh-dashboard-agent-server` | `String` | Agent daemon URL |

### ViewState

[`ViewState` type](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/Storage.purs#L42-L54) captures everything about what is visible:

| Field | Type | Default |
|-------|------|---------|
| `currentPage` | `Page` | `ReposPage` |
| `expanded` | `Maybe String` | `Nothing` |
| `expandedProject` | `Maybe String` | `Nothing` |
| `expandedItems` | `Set String` | `empty` |
| `filterText` | `String` | `""` |
| `hiddenItems` | `Set String` | `empty` |
| `darkTheme` | `Boolean` | `true` |
| `issueLabelFilters` | `Set String` | `empty` |
| `prLabelFilters` | `Set String` | `empty` |
| `workflowStatusFilters` | `Set String` | `empty` |
| `projectRepoFilters` | `Set String` | `empty` |

### IndexedDB Cache

| Database | Store | Key | Schema |
|----------|-------|-----|--------|
| `gh-dashboard-cache` | `responses` | `url` (keyPath) | `{ url, etag, body, fetchedAt }` |

Used by `ghFetch` for ETag-based conditional requests. Cleared on "Reset all" via `FFI.Cache.clearCache`.

### Storage Functions

| Function | Purpose |
|----------|---------|
| `loadToken` / `saveToken` | Load/save encrypted token (async, delegates to `FFI.Storage`) |
| `loadRepoList` / `saveRepoList` | Read/write repo name array (JSON in localStorage) |
| `loadViewState` / `saveViewState` | Read/write full view state as JSON. Sets are encoded as JSON arrays. |
| `loadAgentServer` / `saveAgentServer` | Read/write agent server URL |
| `clearToken` | Remove token from localStorage |
| `clearAll` | Remove token, repos, view state, and crypto key from localStorage |

---

## FFI Modules

Each FFI module pairs a PureScript declaration file with a JavaScript implementation.

### Cache (IndexedDB)

- [`src/FFI/Cache.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Cache.purs#L1-L73) / [`src/FFI/Cache.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Cache.js#L1-L93)
- `getCachedResponse :: String -> Aff (Maybe CachedResponse)` -- look up by URL in IndexedDB
- `putCachedResponse :: String -> String -> String -> Aff Unit` -- store URL, ETag, body + timestamp
- `clearCache :: Aff Unit` -- clear all cached responses
- DB: `gh-dashboard-cache`, store: `responses`, keyPath: `url`
- All operations are best-effort -- errors resolve with fallback values

### Storage (Token Encryption + Export/Import)

- [`src/FFI/Storage.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Storage.purs#L1-L32) / [`src/FFI/Storage.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Storage.js#L1-L251)
- `saveTokenEncrypted :: String -> Effect (Promise Unit)` -- encrypt with random local AES key, store in localStorage
- `loadTokenEncrypted :: Effect (Promise String)` -- decrypt from localStorage. Handles migration from plaintext tokens.
- `exportStorage :: Effect Unit` -- downloads settings as JSON. Token is decrypted from at-rest, re-encrypted with a user passphrase (PBKDF2 100k iterations, SHA-256).
- `importStorage :: Effect Unit` -- opens file picker, decrypts token with passphrase, re-encrypts with local key, restores settings, reloads.
- **At-rest encryption**: Random AES-256-GCM key stored as JWK (`gh-dashboard-crypto-key`). Token stored as `base64(iv12 + ciphertext)`.
- **Export encryption**: `base64(salt16 + iv12 + ciphertext)` with passphrase-derived key.

### Terminal (xterm.js)

- [`src/FFI/Terminal.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Terminal.purs#L1-L27) / [`src/FFI/Terminal.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Terminal.js#L1-L139)
- `attachTerminal :: String -> String -> String -> Effect Unit` -- creates an xterm.js instance in a DOM element, connects via WebSocket, sends terminal size on open/resize, handles drag-to-resize handle
- `destroyTerminal :: String -> Effect Unit` -- tears down a terminal by element ID
- `destroyOrphanedTerminals :: Effect (Array String)` -- cleans up terminals whose DOM container was removed
- Internal `_terminals` object tracks all active terminals by element ID

### Clipboard

- [`src/FFI/Clipboard.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Clipboard.purs#L1-L10) / [`src/FFI/Clipboard.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Clipboard.js#L1-L4)
- `copyToClipboard :: String -> Effect Unit` -- calls `navigator.clipboard.writeText`

### Dialog

- [`src/FFI/Dialog.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Dialog.purs#L1-L7) / [`src/FFI/Dialog.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Dialog.js#L1-L3)
- `confirmDialog :: String -> Effect Boolean` -- calls `window.confirm`

### Theme

- [`src/FFI/Theme.purs`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Theme.purs#L1-L10) / [`src/FFI/Theme.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/FFI/Theme.js#L1-L3)
- `setBodyTheme :: Boolean -> Effect Unit` -- toggles `light-theme` class on `<body>`

### Markdown

- [`src/View/Helpers.js`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/src/View/Helpers.js#L1-L7) -- `parseMarkdownImpl` calls `marked.parse()` if the `marked` library is loaded

---

## Playwright Tests

[`tests/`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/tests/)

| File | Tests | Requires token |
|------|-------|----------------|
| [`unauthenticated.spec.ts`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/tests/unauthenticated.spec.ts#L1-L42) | Login page UI: title, input, empty submit error, text entry | No |
| [`authenticated.spec.ts`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/tests/authenticated.spec.ts#L1-L101) | Dashboard shell: toolbar, tabs, theme toggle, filter, export/import buttons, rate limit | Yes (`GH_DASHBOARD_TOKEN`) |
| [`caching.spec.ts`](https://github.com/lambdasistemi/gh-dashboard/blob/4b69256/tests/caching.spec.ts#L1-L145) | IndexedDB caching: cache population, entry structure, 304 on reload, clear on reset | Yes (`GH_DASHBOARD_TOKEN`) |

---

## Key Conventions

### Toggle keys

Sections are identified by string keys in `expandedItems`:

| Key pattern | Used by |
|-------------|---------|
| `section-issues`, `section-prs`, `section-workflows` | Repo detail sections |
| `hidden-issues`, `hidden-prs` | Hidden item sections |
| `issue-N`, `h-issue-N`, `pr-N`, `h-pr-N` | Individual issue/PR rows |
| `proj-status-<projectId>-<statusName>` | Project status columns |
| `proj-item-<projectId>-<title>` | Individual project items |
| `proj-repo-filter` | Project repo filter panel |

### Item keys

Agent items are keyed as `"owner/repo#N"` throughout:
- `launchedItems` (Set): items with active terminals
- `terminalUrls` (Map): itemKey -> WebSocket URL
- `agentSessions` (Map): itemKey -> session state string
- `agentWorktrees` (Set): items with worktrees on the agent

### Optimistic updates

Project mutations (status change, rename, delete) apply state changes immediately before the API call, then set `error` on failure.

### Dispatch pattern

Handler modules receive a `Dispatch o` callback (= `Action -> HalogenM ...`) to trigger cross-module actions without circular imports.

---

## Directory Tree

```
src/
  Main.purs                   -- Entry point, component, action dispatcher
  Types.purs                  -- Domain newtypes + DecodeJson instances
  Refresh.purs                -- Repo/PR refresh logic
  RepoUtils.purs              -- Pure repo list helpers (filter, reorder, parse)
  Storage.purs                -- localStorage read/write (token, repos, view, agent)
  GitHub.purs                 -- Re-export facade for REST + GraphQL
  GitHub/
    Rest.purs                 -- REST v3 client with ETag-based IndexedDB caching
    GraphQL.purs              -- GraphQL client (projects, mutations, response nav)
  Action/
    Common.purs               -- Shared helpers (Dispatch, toggleSet, persistView,
                                  updateDetail, guardExpanded, termElementId)
    Repos.purs                -- Repo page handlers (issues, PRs, workflows, drag-drop)
    Projects.purs             -- Project page handlers (CRUD, optimistic updates)
    Agent.purs                -- Agent/terminal handlers (launch, detach, stop,
                                  sessions, worktrees)
  View.purs                   -- Top-level render (token form, dashboard, toolbar, toasts)
  View/
    Types.purs                -- Action sum type (54 ctors), State record (48 fields),
                                  Toast, ToastLevel
    RepoTable.purs            -- Repo table rows + badges
    Detail.purs               -- Detail panel compositor
    Issues.purs               -- Issues section (filter, visible/hidden, agent badges)
    PRs.purs                  -- PRs section (CI badges, checks, body)
    Workflows.purs            -- Workflows section (SHA nav, run/job rows)
    Projects.purs             -- Projects view (board table, status columns, session
                                  filter, repo filter, item rows)
    DetailWidgets.purs        -- Reusable buttons (refresh, copy, hide, launch, labels)
    Helpers.purs              -- Shared renderers (markdown, terminal, assignees, dates)
    Helpers.js                -- marked.js FFI
  FFI/
    Cache.purs + .js          -- IndexedDB API response cache (ETag-based)
    Storage.purs + .js        -- AES-256-GCM token encryption, export/import
    Terminal.purs + .js       -- xterm.js + WebSocket terminals
    Clipboard.purs + .js      -- navigator.clipboard
    Dialog.purs + .js         -- window.confirm
    Theme.purs + .js          -- body class toggle
tests/
  unauthenticated.spec.ts     -- Token form UI tests
  authenticated.spec.ts       -- Dashboard shell tests (needs token)
  caching.spec.ts             -- IndexedDB caching tests (needs token)
```
