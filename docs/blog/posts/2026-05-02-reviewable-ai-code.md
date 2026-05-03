---
title: How to Get AI to Write More Reviewable Code
date: 2026-05-02
authors: [andrew]
categories:
  - AI
  - Productivity
---

# How to Get AI to Write More Reviewable Code

A 1,000-line PR is hard to review whether a human or an AI wrote it. Once the AI is doing most of the typing, the bottleneck shifts: the review queue is what slows you down, not the implementation. After shipping a [browser-history feature](https://github.com/plusmobileapps/chef-mate/pull/136) on [Chef-mate](https://github.com/plusmobileapps/chef-mate) — almost 1,000 lines added across 40 files — I wanted to write down the practices that made the diff actually reviewable instead of a wall of generated code.

<!-- more -->

## The problem with AI-generated diffs

Ask an agent for a feature and you typically get back one giant change: schema, repository, view model, screen, navigation wiring, and tests, all squashed into a single commit titled something like *"add browser history"*. Reviewing that is exhausting. You can't tell which lines belong to the database migration vs. the new screen, the diff bounces between layers, and any feedback ("can we extract this composable?") forces a sprawling reset.

The fix isn't to ask the AI to write less code — it's to ask it to deliver the same code in **smaller, atomic, individually-reviewable chunks**.

## 1. Demand commit-per-concern, not feature-per-commit

The Chef-mate PR landed as seven commits, each scoped to one concern:

```text
feat(browser): add BrowserHistory database table
feat(browser): add BrowserHistoryRepository
feat(browser): add BrowserPreferences wrapper
feat(browser): record visits in BrowserViewModel
feat(browser): show recent history in edit-query screen
feat(settings): add app settings screen with browser section
feat(settings): wire app settings sub-screen into more tab
```

Each commit compiles, ships its own tests, and changes one layer of the stack. A reviewer can read commit 1 (just the SQL schema and queries) without holding the screen layer in their head. By commit 5, the data layer is already settled and the diff is purely UI.

The trick is to bake this expectation into the prompt up-front:

> *Implement this in commits scoped per-layer: schema, repository, preferences wrapper, view-model integration, screen, and navigation wiring. Each commit must compile and pass tests on its own. Use conventional commit prefixes with the module as the scope.*

If you don't ask, you'll get one commit. Asking is cheap.

## 2. Make module boundaries do the reviewing for you

Chef-mate splits each feature into a `public` module (interfaces, data classes, Compose screens) and an `impl` module (the concrete implementation, DI bindings, view models). When you tell the AI to add a feature, point it at the boundary:

> *`BrowserHistoryRepository` interface goes in `client/browser/public`. The implementation, DI provider, and tests go in `client/browser/impl`. Don't leak SQLDelight types into the public module.*

This does two things at review time. First, the diff in `public/` is small and reads like a contract — easy to skim. Second, anything surprising in `impl/` can be checked against that contract without leaving the file. If your codebase doesn't already have these seams, the AI will happily mix them; the prompt has to enforce them.

## 3. Tests in the same commit, every time

Every one of the seven commits above either added or extended tests:

- The repository commit added `BrowserHistoryRepositoryImplTest.kt` (101 lines) alongside it.
- The preferences commit added `BrowserPreferencesTest.kt` and `UrlNormalizerTest.kt`.
- The settings commit added `AppSettingsBlocImplTest.kt` (106 lines).

A commit without tests is a commit that asks the reviewer to also write the tests in their head. Make it part of the standing instruction: *no production code lands in a commit that does not also include the test for it.* If the AI claims something is too hard to test, that's signal — usually the seam is wrong, not the test.

## 4. Write the test plan as a runnable checklist

The PR body has a manual test plan that reads like a script:

> - Google search ("lasagna recipe") — confirm `google.com/search?...` is NOT recorded but the resulting recipe URL is.
> - Toggle "Save browsing history" off → list empties, new visits don't record. Toggle back on → previous entries return.
> - Kill and relaunch app — history rows and toggle state both persist.

That checklist has two audiences. For the reviewer, it's the smoke test before approving. For the AI itself, it's the spec — if you put the test plan in the prompt before generating the code, the agent treats those bullets as acceptance criteria. The "Google `/search` is filtered" requirement is the reason `UrlNormalizer` exists at all; it didn't get bolted on, it was generated in the same pass as the feature.

## 5. Let the AI defend its choices in review

One of the review comments on this PR was a single line on the migration:

> *@claude why index this?*

That was a question, not a directive. The bot replied with the rationale — `getRecent` does an `ORDER BY visitedAt DESC LIMIT N`, and an index lets SQLite stop early instead of full-scanning — and then **argued against its own choice**:

> *However, it's probably unnecessary here. Browser history tables stay small (tens to low hundreds of rows for most users), and SQLite is fast enough on small tables that a full scan + sort is negligible. The index adds write overhead on every `recordVisit` upsert with no meaningful read benefit at this scale.*

> *Recommendation: Drop the index.*

This is the most under-used review pattern with AI: ask it to justify decisions, and tell it explicitly that "I added this and it's wrong, drop it" is a valid answer. Reviewers learn fastest from the gap between *what was done* and *why*. The AI can fill that gap on demand if the seams (small commits, focused diffs) make the question askable in the first place.

The other two review comments on this PR — *"create a test module where browser preferences is to be shared across tests"* and *"extract into smaller composable function"* — are the kind of feedback that's only practical to leave when the diff is small enough that the reviewer can see the duplication and the over-long composable. On a 1,000-line monolith, they'd have been buried.

## The pattern

None of this is novel review advice. It's the same playbook good engineers have used on each other for years: small commits, clear scopes, tests with the code they cover, an explicit test plan, and a reviewer who can ask *why*. What changed is that the AI is now the one typing — which means the playbook has to live in the prompt, the repo conventions, and the review tooling, not just in the reviewer's habits.

Code volume is no longer the constraint. Reviewability is. Optimize for that.

## Resources

* [Chef-mate PR #136](https://github.com/plusmobileapps/chef-mate/pull/136) — the PR this post is based on
* [Chef-mate](https://github.com/plusmobileapps/chef-mate) — Github
* [Conventional Commits](https://www.conventionalcommits.org/)
