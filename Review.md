# GMSnagNav 0.5.0 — library review and issue register

Reviewed on **2026-11-03** against published tag **0.5.0**, commit
`199cc2b1e74b477951c13494b55a26479b3d489c`.
[Release](https://github.com/kerker00/GMSnagNav/releases/tag/0.5.0).
Source links below are pinned to that commit; line numbers refer to the release, not a future fix.

This register covers the shared model and action logic, both native renderers, hosted row
content, public API contracts, documentation and test workflows. It records **12 confirmed
issues**, followed by architecture decisions and checks that still need evidence. Findings
were independently reviewed across Core, AppKit and UIKit, then checked with focused probes.
No library implementation was changed during this review.

The host-owned model and shared drop-resolution layer remain useful foundations. The main
correctness gap is ownership of transient work: old editors, queued binding writes, hover
timers and native cell reuse can outlive the intent or element that created them. Address these
before extending drag-session APIs in 0.6. The deep-tree failure also needs an explicit
regression test; iterative indexing alone does not make the complete update path depth-safe.

## Evidence and limits

| Check | Result |
| --- | --- |
| Existing macOS package suite on the released source | **298 tests in 22 suites passed** before adding review probes. |
| Additional shared/AppKit checks | Four shared probes failed; five AppKit probes failed; one AppKit environment-propagation control passed. The hover-disable case was confirmed in isolation. |
| Targeted iOS package checks, authorized for this review | Five UIKit probes executed in an iPad simulator and failed on the released implementation. These exercise native coordinators and key commands, not full pointer/keyboard UI automation. |
| Deep-diff subprocess | A 10,000-level restructuring crashes a debug build; LLDB attributes the recursion to `DiffState.canStayLoaded`. Optimized-build observations are recorded under BUG-001. |
| Manual/hardware acceptance | Hardware VoiceOver, physical keyboard interaction, PreCal workflows and full demo UI suites were not repeated for this review. Earlier release acceptance remains a separate record. |

Local tools: macOS 27.0.1, Xcode 27.2, Apple Swift 6.4.2, Swift 6 language mode.
This does not establish behavior on every supported OS/toolchain combination. The iOS run was
targeted; it was not a fresh run of the entire existing iOS suite.

All confirmed issues below have an executable counterprobe or an isolated crash reproduction.
Where one platform was executed and another shares the same source defect, that distinction
is stated. Proposed fixes and unexecuted acceptance cases are not claimed as verified.

## Register and handling rules

- **P1:** broad or urgent failure requiring immediate attention. None was established at this level by this review.
- **P2:** correctness failure under a specific reproducible condition, including the extreme-depth debug crash.
- **P3:** localized presentation or usability defect.
- **Open:** confirmed and not fixed in the reviewed release. **Decision needed** and **Needs validation** are not confirmed bugs.

Suggested patch target is the next **0.5.x** release; this is a triage proposal, not a committed
release scope. IDs remain stable. When fixing an item, add its regression to the maintained
suite, record the fix commit/PR and verification below, and only then change its status to
Resolved. Keep the reproduction and resolution history. Local implementation scheduling stays
in `PLAN.md`; this file is the versioned review register.

| ID | Priority | Area | Status | Suggested target |
| --- | --- | --- | --- | --- |
| [BUG-001](#bug-001--deep-diff-recursion-can-exhaust-the-stack) | P2 | Shared diff / macOS update path | Open | 0.5.x |
| [BUG-002](#bug-002--an-old-rename-completion-clears-a-new-session) | P2 | Shared renaming | Open | 0.5.x |
| [BUG-003](#bug-003--a-queued-rename-restart-writes-after-detach) | P2 | AppKit renaming | Open | 0.5.x |
| [BUG-004](#bug-004--return-starts-renaming-an-invisible-selected-row) | P2 | AppKit keyboard | Open | 0.5.x |
| [BUG-005](#bug-005--automatic-selection-reveal-outlives-the-selection) | P2 | Shared reveal | Open | 0.5.x |
| [BUG-006](#bug-006--sibling-reordering-uses-stale-pin-state) | P2 | Shared reordering | Open | 0.5.x |
| [BUG-007](#bug-007--reused-mac-cells-retain-another-elements-swiftui-state) | P2 | AppKit hosting | Open | 0.5.x |
| [BUG-008](#bug-008--drop-proposals-ignore-temporary-visible-expansion) | P2 | Both drop renderers | Open | 0.5.x |
| [BUG-009](#bug-009--spring-loading-policy-changes-do-not-reconcile-pending-work) | P2 | Both hover timers | Open | 0.5.x |
| [BUG-010](#bug-010--leaving-the-uikit-drop-target-keeps-spring-loading-alive) | P2 | UIKit drag exit | Open | 0.5.x |
| [BUG-011](#bug-011--forward-arrow-enters-a-row-that-native-focus-rejects) | P2 | UIKit keyboard | Open | 0.5.x |
| [BUG-012](#bug-012--uikit-sibling-shortcut-titles-ignore-the-host-locale) | P3 | UIKit localization | Open | 0.5.x |

## Confirmed issues

### BUG-001 — Deep diff recursion can exhaust the stack

**Source:** [OutlineDiff.swift:81][diff-ancestry]; other recursive paths at
[load:69][diff-load], [visit:93][diff-visit] and [forget:116][diff-forget].
The [README][readme-depth] advertises arbitrarily deep trees.

**Reproduction:** Use non-recursive host values containing only an integer ID. Start with
10,000 empty containers at the root, all in the loaded set. Build the next snapshot as the
chain `9999 → 9998 → … → 0` and call `new.changes(from: old, loaded: Set(0..<10000))`.
The `-Onone` subprocess exits with SIGSEGV. LLDB shows repeated `canStayLoaded` frames at
line 84 and `EXC_BAD_ACCESS`, consistent with stack exhaustion. The host fixture itself does
not store recursive values, so this is not recursive host-model destruction.

**Optimized controls:** At 1,000 nodes, both `-O` and the Swift 6 whole-module-optimized
build completed successfully. At 10,000 nodes, both were stopped by a
30-second subprocess timeout without completing; the WMO run also timed out at 50,000.
No optimized-build crash was confirmed. These diagnostic runs overlapped other work and are
not calibrated benchmarks or completed timings for the larger inputs. Exact build commands
and outcomes are in `/private/tmp/review050-core/Evidence.md`; the observed shell stack limit
was 8,176 KiB.

**Impact and scope:** A valid, unusually deep structural update can crash a debug host app
on the macOS diff path. This is not evidence that ordinary shallow trees crash. Stack limits
and optimization affect the threshold; 10,000 is a reproduced input, not a supported limit.
Do not infer that the iterative `OutlineTree` constructor makes recursive diff helpers safe.

**Suggested fix:** Replace depth-dependent recursive traversals with explicit work stacks.
Memoize loaded-ancestry decisions so eliminating the stack overflow does not leave repeated
walks of the same long chain. Review all four recursive paths, not only the first crashing one.

**Acceptance:** A subprocess regression for the flat-to-deep transition completes in debug
and optimized builds; deep loaded traversal and subtree removal are also covered. Preserve
the existing randomized diff correctness tests. Measure time/memory separately and align the
documented depth claim with tested behavior. See the self-contained probe in the appendix.

### BUG-002 — An old rename completion clears a new session

**Source:** [Renaming.swift:65][rename-session], especially the unconditional binding write at 73.

**Reproduction:** Begin renaming `a1`, retain its session, then set the host rename binding to
`c`. End the old `a1` session. The counterprobe observes `nil`, although `c` is the current
target. A disappearing or losing-focus editor can therefore cancel a newer rename.

**Suggested fix:** Give a rename session ownership of its completion and focus return.
An old session must not clear a newer session's binding. Define whether its old draft should
still commit; do not accidentally discard the documented commit-on-disappearance behavior.
An ID comparison alone may not distinguish two consecutive sessions for the same element.

**Acceptance:** Switching A → B preserves B when A completes; test cancel, commit, focus loss,
disappearance and same-ID restarts. Only the owning session clears the binding or restores focus.
Probe: `endingAnOlderRenameMustNotCancelTheNewTarget` (shared logic, executed on macOS).

### BUG-003 — A queued rename restart writes after detach

**Source:** [AppKitOutlineRenderer.swift:1006][rename-restart]; [detach:222][appkit-detach].

**Reproduction:** Return on a stuck rename clears the binding and records a restart. Let
the next update enqueue that restart, detach the coordinator, then drain the queued task.
The host binding becomes `A` after detach, rather than remaining `nil`.

**Cause/impact:** The untracked task captures the binding and tests only whether it is nil.
The outline no longer exists, yet it can put its host back into a rename state with no editor.
Target removal and withdrawn permission use similarly unguarded paths, but were not separately executed.

**Suggested fix:** Track/cancel the task and validate coordinator generation, target existence,
rename permission and current intent before writing. Clearing `pendingRenameRestart` alone
does not cancel a task that was already enqueued.

**Acceptance:** Detach, target removal, removal of the modifier and a newer rename prevent
the old restart from writing. Normal Return-to-restart still works.
Probe: `queuedRenameRestartDoesNotMutateHostAfterDetach`.

### BUG-004 — Return starts renaming an invisible selected row

**Source:** [AppKitOutlineRenderer.swift:983][return-rename].

**Reproduction:** Keep child `x` selected in the host binding, collapse its parent and disable
automatic selection reveal. There is one visible parent row. Call the Return handler: the
rename binding becomes `x`, although no editor can be mounted for it.

**Cause/impact:** Return uses the host-selected ID without the visibility guard used for
hierarchy/reordering commands. Hidden selection is intentionally retained, but starting an
inaccessible editor can leave rename guards blocking later commands.

**Suggested fix:** Choose an explicit keyboard policy: require a visible selected row, or
reveal it successfully before starting inline rename. Keep host-initiated rename policy separate.

**Acceptance:** Return after collapsing the selected child's parent creates no inaccessible
editor or stuck binding; visible-row renaming, primary-action fallback and retained hidden
selection keep their intended behavior. Probe: `returnDoesNotStartAnEditorForAHiddenSelectedRow`.

### BUG-005 — Automatic selection reveal outlives the selection

**Source:** [Core/SelectionReveal.swift:15][selection-state] and [Reveal.swift:32][selection-task].

**Reproduction:** Two shared counterprobes demonstrate different parts of the same lifetime gap:

1. Record a host-selected hidden descendant `a2x`, then a user selection of root `c`.
   `pending` still names `a2x`; the old scroll request was not cancelled.
2. Schedule automatic expansion for `a2x`, select root `c` before the deferred task runs,
   then drain it. Ancestors `a` and `a2` are still added to the expansion binding.

**Impact:** A superseded selection can open unrelated branches or cause a later scroll to an
old target. The deferred task has no cancellation/generation check. This is the automatic
selection-reveal path; the 0.5.0 hierarchy-reveal fixes do not cover it.

**Suggested fix:** Own pending scroll and deferred binding writes under one reveal request
generation. A superseding host/user selection, reveal being disabled, explicit navigation,
target removal or detach must invalidate the appropriate old request.

**Acceptance:** Both probes pass; clearing selection also clears obsolete pending work.
Test host → host and host → user changes, disable/detach, and precedence with explicit
navigation. A current, unchanged host selection still reveals normally.
Probes: `userSelectionMustCancelPendingAutomaticReveal`,
`aSupersededSelectionMustNotExpandOldAncestors` (executed on macOS; shared by both renderers).

### BUG-006 — Sibling reordering uses stale pin state

**Source:** [Reordering.swift:38][reorder-pins], compared with
[PinnedRows.swift:27][pin-snapshot] and live pin handling in [HierarchyMovement.swift:54][hierarchy-pins].

**Reproduction:** Resolve the rendered behavior while `isPinned` returns false. Change the
host's live pin predicate to true before the next render, then invoke a sibling reorder with
that behavior. It returns true and calls the performer for the now-pinned source.

**Cause/impact:** Rendering replaces `isPinned` with a captured ID set. Sibling execution
uses this captured predicate, although `liveIsPinned` is retained and hierarchy/menu execution
checks current policy. A stale shortcut/VoiceOver action can bypass the package's pin protection.
Hosts should still validate their own model mutations.

**Suggested fix:** Use live policy during action execution and re-resolve source/target pin
rules consistently. Keep snapshot-based display availability inexpensive.

**Acceptance:** Pin changes after rendering block a stale action without calling `perform`;
unpinning and destination-prefix changes are also rechecked. Existing boundary and redirect
tests remain green. Probe: `pinningAfterRenderingMustBlockSiblingReordering`.

### BUG-007 — Reused Mac cells retain another element's SwiftUI state

**Source:** [AppKitOutlineRenderer.swift:346][cell-config], reuse at [699][cell-reuse], and
[HostingCellView.swift:96][hosting-root].

**Reproduction:** Show a same-type custom row for A whose `@State` is initialized from A's ID.
Reuse the `HostingCellView` for B. The hosted row reports `B:A`, not `B:B`.
The counterprobe observed `["A:A", "B:A"]`.

**Cause/impact:** The hosted root is updated without an element identity boundary. AppKit
reuses cells, so custom row toggles, disclosure state or drafts can carry over to another item.
The probe directly exercises the hosting cell used by the renderer; a full scroll gesture was not required.

**Suggested fix:** Key hosted content by stable model ID. Preserve SwiftUI state when the
same element is refreshed, and reset it when the native cell displays a different element.

**Acceptance:** A → B reuse resets element-local state; A → A updates preserve drafts and
focus. Cover real renderer reuse as a regression, including badges/menus and renaming.
Probe: `recycledCellResetsStateForAnotherElement`. UIKit reuse remains a separate validation task.

### BUG-008 — Drop proposals ignore temporary visible expansion

**Source:** [AppKit resolveDrop:655][appkit-drop], [UIKit resolveDrop:893][uikit-drop], and the
public [isTargetExpanded contract][expanded-contract].

**Reproduction:** Spring-open collapsed folder A while the host expansion binding stays
empty, then resolve a drop onto A. AppKit reports the native item as expanded, but the
proposal has `isTargetExpanded == false`. Both renderers pass only bound expansion into
resolution. The AppKit path was executed; the UIKit counterpart is source-confirmed.

**Impact:** A host using the documented flag to choose append/prepend behavior or validation
receives a value that does not match the displayed folder. Opening/closing temporarily also
does not invalidate the cached resolution, so changing the input alone is insufficient.

**Suggested fix:** Resolve native pointer drops against effective displayed expansion and
invalidate affected cached answers when it changes. Keep temporary expansion outside the
host binding. Explicit menus without a mounted outline continue using their supplied expansion.

**Acceptance:** Validate the same target before opening, after spring-opening and after closing.
The flag follows displayed state and affected validation is rerun; redirects use the final
target's effective expansion. Probe: `springLoadedFolderReportsItsVisibleExpansionInDropProposal`.

### BUG-009 — Spring-loading policy changes do not reconcile pending work

**Source:** [AppKit hover:569][appkit-hover] and [UIKit hover:967][uikit-hover].

**Reproduction:** Schedule a delayed hover-open, change `springLoadingBehavior` to `.disabled`
and update before the delay expires. Both executed platform probes still open the folder.
The task checks cancellation and candidate identity, but not current policy.

**Related source path:** Hovering while disabled stores a candidate without a timer. Enabling
while still over that same candidate can return early instead of scheduling. This reverse
transition follows from the source but still needs its own runtime regression.

**Suggested fix:** Reconcile pending hover state when configuration changes and revalidate
current permission immediately before opening. Define how disabling treats an already-open
temporary branch; clear/reschedule candidates without requiring pointer exit/re-entry.

**Acceptance:** Disable during delay prevents opening on both platforms; enable during a
stationary hover starts a fresh timer. Test changed system preference on macOS and preserve
host-owned expansion. Probes: `disablingSpringLoadingCancelsAPendingTimer` (AppKit),
`disablingSpringLoadingCancelsAnAlreadyScheduledOpen` (UIKit).

### BUG-010 — Leaving the UIKit drop target keeps spring-loading alive

**Source:** [UIKit dropSessionDidExit:917][uikit-exit], compared with cleanup at [924][uikit-end].

**Reproduction:** Hover over a collapsed folder, invoke the native drop-exit callback before
the timer expires, then await pending work. The folder still opens. A second probe exits
after opening; the temporary branch remains open. The host expansion binding remains empty.

**Cause/impact:** Exit clears only the drop indicator; it does not cancel the timer or restore
temporary expansion. Cleanup waits until the drag session ends. A folder can therefore open
after the finger has left the outline, contrary to the documented hover behavior.

**Suggested fix:** End target-local hover work and restore temporary expansion on exit.
Preserve the overall source drag session so it can re-enter or complete elsewhere.

**Acceptance:** Exit before delay prevents opening; exit after opening restores bound
expansion; a host-expanded folder remains open. Re-entry can schedule a fresh hover, and
session end remains idempotent. Probes: `exitingDropTargetCancelsPendingSpringLoading`,
`exitingDropTargetClosesTemporaryExpansion` (both executed in the simulator).

### BUG-011 — Forward arrow enters a row that native focus rejects

**Source:** [UIKit expand handling:601][uikit-expand], [focus:655][uikit-focus], compared with
the [native focus predicate:688][uikit-focusable].

**Reproduction:** Expand a container whose first child is an excluded, unselectable leaf and
whose second child is selectable. With the container selected, press the forward-arrow action.
The delegate rejects focus for the first child, yet `focusedItemID` becomes that child and
selection remains on the parent instead of reaching the eligible second child.

**Cause/impact:** Hierarchy entry calls `focus(children.first)` without the eligibility check
used for vertical movement and native focus. Logical keyboard position and native focus can
diverge, affecting subsequent navigation and activation.

**Suggested fix:** Share a focusability policy across hierarchy entry, vertical movement and
the focus delegate. Skip excluded leaves; keep unselectable containers/headers navigable.

**Acceptance:** Enter the first eligible child, keep the parent if no eligible child exists,
and test nonselectable containers plus RTL mapping. Logical focus, native focus and selection
follow the chosen contract. Probe: `forwardArrowSkipsAnUnfocusableFirstChild`.

### BUG-012 — UIKit sibling shortcut titles ignore the host locale

**Source:** [SnagCollectionView.swift:99][uikit-command-labels], especially 120–121;
compare the explicit locale used for [hierarchy commands:140][uikit-hierarchy-labels].

**Reproduction:** Override `outlineLocale` with English on a simulator whose process locale
is German, and read Command-Option-Up's title. It remains `Nach oben verschieben`, not
`Move Up`. The lazy sibling commands localize once from the process locale; they never read
subsequent host-locale changes, unlike the hierarchy commands.

**Suggested fix:** Refresh sibling discoverability titles from the live host locale while
preserving command registration, routing and editor priority.

**Acceptance:** English → German → English updates Move Up and Move Down on the same view,
alongside hierarchy command titles; shortcut behavior stays stable.
Probe: `siblingShortcutTitlesFollowLiveHostLocale`.

## Architecture decisions for the roadmap

These are design work, not additional confirmed bugs. Milestones follow the
[released roadmap][roadmap]; changes to scope need a separate decision.

| ID | Status | Decision and required outcome | Milestone |
| --- | --- | --- | --- |
| ARCH-001 | Decision needed | Give deferred native effects explicit owners, generations and cancellation rules. Reuse the stronger navigation/hierarchy-driver pattern for rename restart and automatic reveal; define valid cleanup of old drafts separately from new-session writes. Include detach, removed targets, policy changes and superseding intent. Test effects through deterministic settlement hooks. | Fix foundations in 0.5.x; before 0.6 API work |
| ARCH-002 | Decision needed | Model drag source sessions and destination hover state explicitly. Tokens, dragged IDs, pending target, cache, captured row frames and temporary expansion currently have independent cleanup. Define begin/update/final outcome and idempotent teardown across native and hosted-menu drag paths. A destination exit ends hover, not necessarily the source drag. Exactly one terminal lifecycle notification must correspond to each started session. | Before 0.6 previews/lifecycle callbacks |
| ARCH-003 | Decision needed | Centralize EditMode selection and activation policy. Decide whether the next visible tap preserves hidden selected IDs: collapse retains them today, but UIKit rebuilds multiple selection from native visible rows on the next write. Specify selection vs primary actions, deletion, sections, keyboard focus, rename/drag interaction and external model changes while editing. | Before 0.7 |
| ARCH-004 | Decision needed | Keep local synchronous proposals separate from asynchronous incoming/outgoing payload handling. Specify payload types/versioning, origin/session identity, decode progress/errors, cancellation, host validation and commit ownership. Define partial decode/import policy and move acknowledgement. The current synchronous `Bool` performer and coordinator-local IDs cannot describe cross-app transfer completion by themselves. | Before 0.8 |
| ARCH-005 | Planned investigation | Establish wide/deep benchmarks before choosing caches, diff shortcuts or lazy snapshots. Measure host-provider reads and validation costs separately from package work. Do not reintroduce stale action snapshots to avoid rebuilding trees. See the measurement matrix below. | Regression budgets now; full measurements by 0.9 |
| ARCH-006 | Decision needed | For asynchronous children, distinguish leaf, unloaded, loading, loaded-empty and failed/retry. Define whether an unloaded container discloses, who starts/cancels loading, how stale results are rejected, and what reveal/search/drop mean before descendants are known. The current `nil`/array children contract cannot express all of these states. Keep loading/persistence in the host. | Evaluate after benchmarks, as the roadmap states |
| ARCH-007 | Decision needed | Before API stability, document callback isolation/reentrancy, live vs snapshot eligibility, pointer-cache invalidation, hidden selection/focus, rename ownership, pin protection, effect cancellation, failure results and supported size/depth evidence. Add host integration examples for atomic moves/copies, undo and error reporting. Define a support/compatibility matrix and migration guidance. | 1.0 gate |

**Refresh proposal:** A separate roadmap draft (`docs/roadmap-pull-to-refresh`, `07ded52`)
proposes pull-to-refresh for 0.7; it is not part of the reviewed release's roadmap.
If adopted, forward the host's refresh
action into the native control and define overlap, cancellation, errors/retry and late-result
handling. Keep selection/expansion stable and avoid a second mutable data source.

### Performance work that needs measurements

Existing source patterns justify benchmarks, not a blanket claim that ordinary trees are slow:

- [SnagOutline.body][body-index] indexes the full host tree, including collapsed descendants.
- [UIKit snapshots][uikit-snapshot] contain the whole hierarchy; [expansion reconciliation][uikit-expansion] scans applied items.
- [AppKit refreshVisibleRows][appkit-refresh] scans displayed row indices and updates instantiated cells on each update.
- [Destination menus][menu-build] build a fresh tree per call; Move and Copy are separate calls. The 0.5.0 preparation fixes already avoid repeated per-target source preparation; do not report the old PR-61 defect again.
- [Source normalization][normalization] constructs ancestor/index paths, [pinned-prefix lookup][pin-prefix] scans siblings, and diff placement searches/moves arrays. Adverse shapes and many selected sources need separate measurement.
- UIKit drop-indicator changes refresh visible content; compare refreshing only affected rows with the current approach before changing rendering behavior.

Measure **1,000 / 10,000 / 50,000 elements**, wide and deep, mostly collapsed and fully
expanded. Include initial mount, expansion, no-structure content updates, selection, paired
menus, sibling reversal, reparenting and active drag feedback. Record indexing/diff/snapshot
build/apply time, main-thread stalls, allocations/peak memory, provider reads and validator
calls. Use multiple runs and named hardware/build configurations; set budgets only after
collecting a baseline. Deep-diff crash tests should run in a subprocess so failure cannot kill
the entire test runner. Do not present a timeout as a completed timing measurement.

## Validation and integration backlog

| ID | Status | Evidence, next check and completion criterion |
| --- | --- | --- |
| QA-001 | Open documentation/measurement gap | [CI][ci] measures coverage only for macOS; UIKit is excluded, as its summary correctly states. The [badge workflow][coverage-badge] still labels this simply `coverage`. Label the scope explicitly and publish separate iOS coverage if useful. Do not use the macOS percentage as evidence for UIKit behavior. |
| QA-002 | Needs validation / automation work | CI runs package tests on macOS/iOS, not demo UI suites. Add the new regressions at the lowest useful layer, then run targeted native workflows for fixes. Keep UI checks separately visible. Replace arbitrary yield/sleep polling where necessary with settlement hooks; retain at least one end-to-end check for keyboard focus and row reuse. |
| QA-003 | Needs validation | The demo's [accessibility audit][audit] retains a narrow, non-strict expected failure for an unresolved section Dynamic Type report with no element. It was not reproduced in this review. Inspect sections at accessibility sizes and real VoiceOver expanded/collapsed state, action names, rename transitions and focus. Historical duplicate AX identifiers/extra Move image need current evidence before being labelled current bugs. Existing release hardware acceptance is not revoked by this backlog. |
| QA-004 | Needs validation | UIKit row hosting has no explicit model-ID boundary, but `UIHostingConfiguration` may reset state itself; the AppKit result does not prove an iOS bug. Probe reuse with stateful rows and same-ID refresh. Also test host-locale overrides on VoiceOver hierarchy actions: locale injection is inside `ReorderingAccessibility`, whose own environment read may observe a different scope. Promote only after a focused rendering/AX reproduction. |
| QA-005 | Needs contract/integration checks | Revalidate real host integration after fixes: filtered index compatibility, rapid model changes, rejected/failed performers, undo, deleted selections and copy-ID selection. Check macOS Option-click/Option-arrow recursive expansion against the binding and document delete-command forwarding with a native first responder. These inherited integration questions were not settled by this review. |
| QA-006 | Needs owner decision | Branch protection/required checks and the default branch are repository administration choices. This review inspected workflow files, not current GitHub rulesets. Verify required checks before treating them as enforced release gates. |

## Previously reported issues and intentional boundaries

- The earlier PR-61 menu atomicity, inactive submenus and AppKit menu/sibling-label fixes are
  present in this release. The current menu path retains raw source IDs and resolves against
  live data on invocation. No new defect in that atomicity path was established here.
- PR-62 hierarchy availability no longer rebuilds a live tree before the opt-in guard; display
  availability uses the renderer snapshot. A later structure change cancels a queued hierarchy
  reveal. BUG-005 concerns the separate automatic selection path.
- Historical missing hardware-keyboard navigation, native `outlineContextMenuItems` menus,
  RTL chevron handling and all audit/UI-test coverage should not be carried forward as wholly
  absent features. Native menus and tests now exist. Remaining performance and accessibility
  questions are tracked above. SwiftUI context menus remain an intentional alternative.
- The AppKit environment control confirmed RTL and disabled-state propagation. There is no
  confirmed general hosted-environment loss.
- Drops onto leaves may be redirected by the host. This is deliberate, not a missing package
  rejection. Duplicate IDs violate the documented tree identity contract.
- The host owns persistence, atomic mutation/rollback, model errors, sorting/filter index
  compatibility and selection of newly created copy IDs. A `perform` returning false is not
  evidence that the package partially mutated data; the package does not perform that mutation.
- Pointer validation caching is documented and invalidated on renderer updates. Policy changes
  with no update are not a separate confirmed cache bug here. BUG-008 concerns a package-owned
  expansion change that does not reach the bound-expansion input or invalidation path.
- Cross-view/external transfers and asynchronous child loading are future scope, not missing
  behavior contrary to the current same-outline synchronous contract.

## Suggested work packages

Keep fixes independently reviewable; add the relevant failing regression before each fix.

| Order | Package | Issues | Completion gate |
| --- | --- | --- | --- |
| 1 | Depth-safe diff and bounded regression fixtures | BUG-001 | Debug/optimized subprocesses and existing diff tests; measured completion, no runner crash. |
| 2 | Rename ownership, restart cancellation and visible keyboard targets | BUG-002–004; part of ARCH-001 | Shared tests, native AppKit regressions, targeted rename/focus workflow. Keep each distinct fix in its own commit where practical. |
| 3 | Automatic reveal cancellation | BUG-005; part of ARCH-001 | Supersession/disable/detach cases plus current-selection reveal on both native adapters. |
| 4 | Live pin checks for explicit sibling actions | BUG-006 | Stale action and pin-prefix tests; no performer call for a newly pinned source. |
| 5 | Stable hosted row identity | BUG-007; QA-004 reuse check | Different-ID reset and same-ID draft/focus preservation. |
| 6 | Destination hover lifecycle and effective expansion | BUG-008–010; foundation for ARCH-002 | Separate commits for proposal/cache correctness, policy changes and UIKit exit; native tests on both platforms. |
| 7 | UIKit keyboard consistency and live localization | BUG-011–012 | Excluded-row/RTL focus checks and English/German title transitions. |
| 8 | Close patch acceptance and prepare 0.6 design | QA-001–005; ARCH-001–002 | Existing platform suites, relevant native UI checks, documented hardware/integration results; lifecycle contract reviewed before new public hooks. |

Avoid bundling new 0.6 features into these fixes. Once regression coverage and ownership rules
are in place, continue the published feature order. Benchmarks and lazy-loading design remain
separate deliverables; a 1.0 decision should rely on the contracts and evidence in ARCH-007,
not merely on finishing a list of features.

## Reproduction appendix

The review used detached worktree `/private/tmp/GMSnagNav-library-review-050` at the exact
release commit. Only temporary counterprobe files were added there. They are not maintained
package tests and should be ported into the normal suites with each fix. Temporary paths are
local evidence locations, not durable CI artifacts; the triggers and acceptance criteria above
are the lasting record.

| Local evidence | Contents |
| --- | --- |
| `/private/tmp/GMSnagNav-library-review-050-baseline.log` | Unmodified-source macOS baseline, 298 passing tests. |
| `Tests/GMSnagNavTests/Review050Counterprobes.swift` in the review worktree | Four shared probes for BUG-002, BUG-005 and BUG-006. |
| `Tests/GMSnagNavTests/Review050AppKitProbes.swift` in the review worktree | Five AppKit defect probes plus the passing environment control. |
| `/private/tmp/GMSnagNav-library-review-050-native-counterprobes.log` | Initial combined shared/AppKit run. |
| `/private/tmp/GMSnagNav-library-review-050-extra-appkit.log` | Isolated hover-disable confirmation and hidden-row rename reproduction. |
| `Tests/GMSnagNavTests/UIKit/Review050UIKitRegression.swift` and `Review050DropSession.swift` in the review worktree | Five UIKit tests and the drop-session stub. |
| `/private/tmp/GMSnagNav-library-review-050-ios.xcresult` and `.log` | Five executed UIKit probes; all fail as expected on 0.5.0. |
| `/private/tmp/GMSnagNav-library-review-050-ios-confirmed.xcresult` and `.log` | Five probes executed again after extending the locale test to English → German → English; all five fail, including both English-title assertions. |
| `/private/tmp/review050-core/DeepDiffProbe.swift` | Standalone deep-diff input. |
| `/private/tmp/review050-core/deep-diff-debug-lldb.txt` | Crash stack with repeated `OutlineDiff.swift:84` frames. |
| `/private/tmp/review050-core/Evidence.md` | Optimized build commands, completed small controls, timeouts and measurement limits. |

Run package probes only from the isolated review worktree after inspecting their source:

```sh
swift test --filter 'Review050Counterprobes|AppKitReviewProbes'
xcodebuild test -scheme GMSnagNav \
  -destination 'platform=iOS Simulator,id=CB840549-134A-4D1B-8A56-F9A3F49FC5BE' \
  -parallel-testing-enabled NO \
  -only-testing:GMSnagNavTests/ReviewUIKitRegression \
  CODE_SIGNING_ALLOWED=NO
```

Use an available destination on other machines. These commands intentionally reproduce
failures until the corresponding implementation is fixed. A follow-up method-only Xcode
filter selected zero tests and is not evidence of a pass; the suite-level run selected five.

Standalone deep-diff input, compiled together with the three listed release sources:

```swift
struct ProbeItem: Identifiable { let id: Int }

@main
struct DeepDiffProbe {
  static func main() {
    let count = Int(CommandLine.arguments.dropFirst().first ?? "10000")!
    let old = OutlineTree((0..<count).map(ProbeItem.init)) { _ in [ProbeItem]() }
    let new = OutlineTree([ProbeItem(id: count - 1)]) { item in
      item.id > 0 ? [ProbeItem(id: item.id - 1)] : []
    }
    let changes = new.changes(from: old, loaded: Set(0..<count))
    print("nodes=\(count) changes=\(changes.count)")
  }
}
```

```sh
xcrun swiftc -swift-version 6 -g -Onone \
  Sources/GMSnagNav/Core/OutlineTree.swift \
  Sources/GMSnagNav/Core/ExpansionChanges.swift \
  Sources/GMSnagNav/Core/OutlineDiff.swift \
  /private/tmp/review050-core/DeepDiffProbe.swift \
  -o /private/tmp/review050-core/deep-diff-probe
xcrun lldb --batch -o run -k 'bt 16' -- \
  /private/tmp/review050-core/deep-diff-probe 10000
```

Run stress inputs with a process timeout; do not put this crashing fixture directly into an
in-process test suite. Use a small completed control and record optimization, hardware and
stack configuration when comparing results.

## Resolution history

No fixes are included in this review. For each completed issue, append the fix commit/PR,
regression names, tested configurations and remaining limitations, then update the register.

[diff-ancestry]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDiff.swift#L81-L84
[diff-load]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDiff.swift#L69-L75
[diff-visit]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDiff.swift#L93-L103
[diff-forget]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDiff.swift#L116-L120
[readme-depth]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/README.md#L37-L39
[rename-session]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Renaming.swift#L65-L75
[rename-restart]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L1006-L1014
[appkit-detach]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L222-L229
[return-rename]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L983-L998
[selection-state]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/SelectionReveal.swift#L15-L38
[selection-task]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Reveal.swift#L32-L43
[reorder-pins]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Reordering.swift#L38-L66
[pin-snapshot]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/PinnedRows.swift#L27-L40
[hierarchy-pins]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/HierarchyMovement.swift#L43-L58
[cell-config]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L346-L347
[cell-reuse]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L695-L703
[hosting-root]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/HostingCellView.swift#L95-L108
[appkit-drop]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L655-L660
[uikit-drop]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L893-L897
[expanded-contract]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDrop.swift#L90-L94
[appkit-hover]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L569-L579
[uikit-hover]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L967-L977
[uikit-exit]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L917-L921
[uikit-end]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L924-L931
[uikit-expand]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L601-L605
[uikit-focus]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L655-L664
[uikit-focusable]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L688-L692
[uikit-command-labels]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/SnagCollectionView.swift#L99-L123
[uikit-hierarchy-labels]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/SnagCollectionView.swift#L128-L141
[roadmap]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/README.md#L250-L270
[body-index]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/SnagOutline.swift#L135-L138
[uikit-snapshot]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L319-L330
[uikit-expansion]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/UIKit/UIKitOutlineRenderer.swift#L188-L193
[appkit-refresh]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/AppKit/AppKitOutlineRenderer.swift#L332-L342
[menu-build]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/OutlineActions.swift#L77-L92
[normalization]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/Core/OutlineDrop.swift#L178-L182
[pin-prefix]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Sources/GMSnagNav/PinnedRows.swift#L45-L53
[ci]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/.github/workflows/ci.yml
[coverage-badge]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/.github/workflows/coverage-badge.yml#L24-L41
[audit]: https://github.com/kerker00/GMSnagNav/blob/199cc2b1e74b477951c13494b55a26479b3d489c/Examples/SnagNavDemo/SnagNavDemoUITests/SidebarUITests.swift#L487-L501
