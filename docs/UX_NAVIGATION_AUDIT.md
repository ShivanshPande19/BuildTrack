# BuildTrack — UX / Navigation Audit (Tier 3 blueprint)

**Status:** proposal / blueprint. No code changed by this document — it maps what exists,
names the confusion, and proposes a cleaner information architecture (IA) to implement
next, so we agree on the target before touching screens.

**Why this exists:** the app is functionally complete, but it *feels* confusing —
"the same thing is reachable from two places" and it isn't always clear what a screen is
for. The two north-star goals (see `.kiro/steering/product.md`): **easy to understand**,
**easy to create things**, and the rule **one action = one place**.

Everything below is grounded in the current code (file references included).

---

## 1. Current information architecture (what ships today)

Each role logs in → `role_home.dart` routes to that role's home shell (a floating
`PillNav` with 3–4 tabs + one circular action button "FAB").

| Role | Tabs | FAB (＋) does | Profile reached via |
|---|---|---|---|
| 👑 Admin | Home · Projects · Team · Insights | **Team tab → Add member, every other tab → Onboard project** | avatar → `ProfileScreen` |
| 📋 PM | My Builds · Projects · Schedule · Team | Assign work | avatar → `ProfileScreen` |
| 🛒 Procurement | To Order · Orders · Receive · Vendors | **Vendors tab → Add vendor, else → New PO** | avatar → `ProfileScreen` |
| 📦 Store | Inbox · Stock · Parts | Log component (scan) | avatar → `ProfileScreen` |
| 🔧 Workshop | Tasks · Parts · Week | Scan to install | avatar → `ProfileScreen` |
| 🎨 Design | Studio · Designs · Approvals | New design | avatar → `ProfileScreen` |
| 🛠️ Service | Tickets · Trucks · Warranty · **Profile** | New ticket | **inline Profile tab** |
| 🙋 Client | My Trucks · Support · **Profile** | (raise request from a truck) | **inline Profile tab** |

Every header carries a **bell → `NotificationsScreen`** and (for 6 roles) an
**avatar → `ProfileScreen`**.

---

## 2. Shared / reused screens and their entry points

These screens are reached from more than one place — the source of most "déjà-vu"
navigation.

| Screen | Reached from | Notes |
|---|---|---|
| `NotificationsScreen` | bell in all 8 role headers; "Notifications" row in the Service & common Profile | Global feed — multiple entries are fine, but it's on both the bell **and** a profile row. |
| `ProfileScreen` (`common/profile.dart`) | avatar in Admin/PM/Procurement/Store/Workshop/Design | **Service & Client don't use it** — they have their own inline Profile tab (different code, different layout). |
| `ProjectDetailScreen` (`admin/project_detail.dart`) | Admin Projects tab (`canAssignPm`); Ops Center → Dossier → *Open build controls* (`canAssignPm`); PM Projects tab & Schedule (`materialsEditable+canAssign+canEditTimeline`) | **One screen, four capability modes set by flags.** Looks identical; what you can do silently depends on how you got there. |
| `ProjectRequirementsScreen` | Project detail → Materials (Admin read-only vs PM `editable`) | Same screen, editability by flag. |
| `NewPoScreen` | Procurement FAB (blank); To-Order card (pre-filled from a requirement); Store reorder; PO detail → *Fix & resubmit* (edit) | The intended "single raise path" — 4 entries, all legitimate, but worth knowing. |
| `PoApprovalsScreen` | **Admin dashboard** *and* **PM home** | Same shared inbox surfaced on two role homes (role-filtered inside). |
| A build **stage** | `StageDetailScreen` (Admin/PM oversight, from the project timeline); `TaskDetailScreen` (Workshop, actionable); the evidence block inside PM **Approvals** | **Three different screens render the same stage's photos/checklist/parts.** |
| `TruckRecordScreen` | Ops Center → Dossier → *Truck record* | Single path. |

---

## 3. Findings — duplicate paths & confusing IA

Severity: 🔴 high (actively confusing / the user's stated pain) · 🟡 medium · 🟢 low.

### 🔴 D. Admin has 3–4 overlapping ways to look at a build
Admin can reach a build through **two routes that land on different screens**:
- Home → **Command Center** (`OpsCenterScreen`, the factory board) → tap a build → **`ProjectDossierScreen`** (the "story": pipeline + delays) → *Open build controls* → **`ProjectDetailScreen`**.
- **Projects tab** → tap a build → **`ProjectDetailScreen`** directly.

So "open build AZ-114" gives you *either* the Dossier *or* the Detail depending on which tab you started in, and the Dossier itself then links onward to Detail, Requirements and Truck Record. Four surfaces (`OpsCenter`, `Projects`, `Dossier`, `Detail` + `Requirements` + `TruckRecord`) describe one build with heavy overlap. **This is the core "same thing, many places" problem.**
Evidence: `admin_dashboard.dart` (Command Center card + Projects tab), `ops_center.dart`, `project_dossier.dart` (→ TruckRecord, → ProjectDetail), `project_detail.dart`.

### 🔴 C. `ProjectDetailScreen` is one screen wearing four hats
The same screen is opened as: Admin oversight (`canAssignPm`), PM full-edit
(`materialsEditable + canAssign + canEditTimeline`), and from the Dossier. Nothing on the
screen tells you which mode you're in — an Admin sees a build that *looks* editable but
mostly isn't, and a PM sees the same layout that *is*. The capability is invisible.
Evidence: `pm_home.dart:318, :437`, `admin_dashboard.dart:462`, `project_dossier.dart:154`.

### 🟡 A. Two Profile implementations + two access patterns
6 roles open the shared `ProfileScreen` from the header **avatar**; Service & Client have a
separate **inline Profile tab** with their own layout. Result: the profile looks and
behaves differently across roles, and "where's my profile?" has two answers (avatar vs
a tab). The shared `ProfileScreen` is also mostly coming-soon stubs.
Evidence: `common/profile.dart`, `service_home.dart` `_ProfileTab`, `client_home.dart` `_profileTab`.

### 🟡 E. A stage is presented by three different screens
`StageDetailScreen` (read-only evidence for Admin/PM), `TaskDetailScreen` (the doer's
actionable view), and the evidence block inside PM **Approvals** each render the same
photos/checklist/installed-parts with slightly different code. Roles genuinely need
different *actions*, but the read-only *presentation* is triplicated and drifts.
Evidence: `admin/stage_detail.dart`, `workshop/task_detail.dart`, `pm/approvals.dart` `_evidence`.

### 🟡 F. Procurement's PO lifecycle is spread across 7 surfaces
`To Order`, `Orders`, `Receive`, `PO Approvals` (also on Admin/PM home), `New PO`,
`PO detail`, `PO document`. The **approval** state and the **fulfilment** state
(ordered→dispatched→received) live in different places, so "where is this PO?" needs
several screens. Not wrong, but heavy.
Evidence: `procurement_home.dart`, `po_detail.dart`, `po_approvals.dart`, `po_document.dart`.

### 🟡 G. The FAB means different things depending on the tab
Admin's ＋ is "Onboard project" on 3 tabs but "Add member" on the Team tab; Procurement's
＋ is "New PO" on 3 tabs but "Add vendor" on the Vendors tab. A primary action button
that changes identity as you switch tabs is easy to misfire.
Evidence: `admin_dashboard.dart:32-34`, `procurement_home.dart:43-44`.

### 🟢 B. Bell + a "Notifications" row both open the same feed
Minor redundancy (`NotificationsScreen` reachable from the header bell and a profile row).

### 🟢 H. Inconsistent back affordance
Most pushed screens use the custom circular `chevron_left` chip; a couple still use a raw
Material `AppBar` back button (e.g. the bill viewer / photo viewer). Small visual drift.

---

## 4. Proposed IA / north-star

The theme: **collapse the many overlapping "build" and "stage" surfaces into one canonical
screen each, and make role differences explicit instead of hidden behind flags.**

### 4.1 One canonical **Build** screen (fixes D, C, and folds in E)
A single `BuildScreen(projectId)` with **tabs**, replacing the Detail/Dossier/Requirements/
TruckRecord sprawl:

```
Build · AZ-114                                   [role mode banner]
┌ Overview ┬ Pipeline ┬ Materials ┬ Record ┐
│ progress, current stage, PM, delivery date, status
│ Pipeline: every stage (planned vs actual, delays, assignee) — read-only,
│           with the doer's evidence inline (shared StageEvidence widget)
│ Materials: order-by list  (editable for PM, read-only for Admin)
│ Record:    installed components + documents (the digital twin)
└
```
- **Every entry point deep-links to the same screen** at the right tab: Projects list,
  Command Center row, Schedule row, Dossier link → all open `BuildScreen`. No more
  Dossier-vs-Detail fork.
- **Mode is explicit:** a small banner/pill at the top — "Oversight (read-only)" for Admin
  vs "You manage this build" for the PM — instead of silent capability flags. The
  editable controls (assign, change date, edit materials, mark delivered) only render in
  PM mode; Admin sees the PM-assign control only.
- **Command Center** stays as a *filtered lens* ("what needs attention right now") whose
  rows deep-link into `BuildScreen` — it stops being a parallel destination.

### 4.2 One **Stage** presentation (fixes E)
Extract a shared `StageEvidence` widget (photos · checklist · installed parts) used by:
the Build → Pipeline tab, Workshop `TaskDetail`, and PM `Approvals`. Each caller adds only
its own *actions* (Workshop: start/submit/scan; PM: approve/reject; Admin/PM: read-only).
One source of truth for how a stage reads.

### 4.3 Unify **Profile** (fixes A)
Pick one pattern for all 8 roles. Recommended: a **Profile tab** in every role's PillNav
(consistent with Service/Client, and a tab is more discoverable than a tiny avatar), all
rendering the same `ProfileScreen` body. Remove the divergent inline copies. Keep the bell
as the only entry to notifications (drop the duplicate profile row) — or keep both, low
priority (B).

### 4.4 A **stable FAB** per role (fixes G)
The ＋ button does **one** thing per role, regardless of tab:
- Admin → Onboard project. "Add member" moves to a ＋ affordance in the **Team tab header**.
- Procurement → New PO. "Add vendor" moves to a ＋ in the **Vendors tab header**.
Secondary "create" actions belong to their own section, not the global FAB.

### 4.5 Procurement PO consolidation (eases F) — optional/second wave
Give a PO **one detail screen** that shows *both* lifecycles (approval + fulfilment) as one
timeline, and treat `To Order → New PO → Approvals → Receive` as a labelled pipeline rather
than four unrelated tabs. Lower priority than the build/stage work.

---

## 5. Prioritized roadmap

| # | Change | Fixes | Impact | Effort | Notes |
|---|---|---|---|---|---|
| 1 | **Canonical `BuildScreen` with tabs** + deep-link all entry points to it | D, C | 🔴 highest | L | Fold Detail + Dossier + Requirements + TruckRecord; Command Center becomes a lens. Do this first — it removes the biggest confusion. |
| 2 | **Explicit role-mode banner** on the build screen | C | high | S | Can ship even before full consolidation as a quick win. |
| 3 | **Shared `StageEvidence` widget** | E | med | M | Also removes drift bugs between the 3 copies. |
| 4 | **Unify Profile** (one pattern, one body) | A | med | S–M | Consistency + discoverability. |
| 5 | **Stable FAB per role**; move secondary creates into tab headers | G | med | S | Small but reduces misfires. |
| 6 | **PO one-detail consolidation** | F | med | L | Second wave; larger. |
| 7 | Bell-only notifications; unify back affordance | B, H | low | S | Cleanup pass. |

Suggested sequencing: **#2 (quick win) → #1 (the big one) → #3 → #4 → #5**, then #6/#7.

---

## 6. Open questions (decide before implementation)

1. **Profile pattern:** a Profile **tab** for every role (recommended), or keep the
   header **avatar → ProfileScreen** everywhere and drop the inline tabs? (Pick one.)
2. **Build screen tabs:** is `Overview · Pipeline · Materials · Record` the right cut, or
   do you want `Materials` and `Record` merged, or a separate `Team/assignments` tab?
3. **Command Center:** keep it as a separate "needs attention" lens (recommended) or fold
   it into the Admin **Projects** tab as a filter?
4. **Scope of the first PR:** just #1+#2 (the build consolidation — highest impact), or a
   wider sweep including #3–#5?

> Nothing here is built yet. Once you pick answers to §6 (especially #1 and #4), the
> first implementation PR is the canonical Build screen — everything else stacks on top.
