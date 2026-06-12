---
title: 'Kotlin Multiplatform UI Text Model'
date: 2026-06-11
authors: ['andrew']
description: >
  Separating domain state from localized UI text in Kotlin Multiplatform with TextData.
categories:
  - 'Multiplatform'
tags:
  - 'text-data'
  - 'kotlin'
  - 'compose'
---

# Kotlin Multiplatform UI Text Models With TextData

One of the small architecture rules I have been using in [Chef Mate](https://github.com/Plus-Mobile-Apps/chef-mate) is this:

> Always expose text from a view model to UI code as `TextData`.

The view model can still keep strongly typed domain state internally. In fact, it should. But the public state model that the UI collects should not force composables to understand domain errors, validation states, or feature-specific enums just to show a message on screen.

<!-- more -->

The UI should receive a text model, localize it, and render it.

## The problem

In a Kotlin Multiplatform app, it is tempting to expose errors directly from shared presentation logic:

```kotlin
data class State(
  val error: SignInError?,
)

sealed interface SignInError {
  data object InvalidEmail : SignInError
  data object InvalidPassword : SignInError
  data object NetworkUnavailable : SignInError
}
```

That seems clean at first because `SignInError` is strongly typed and easy to test. The problem shows up once that state crosses into UI code.

```kotlin
@Composable
fun SignInScreen(state: State) {
  val errorMessage = when (state.error) {
    SignInError.InvalidEmail -> stringResource(Res.string.invalid_email)
    SignInError.InvalidPassword -> stringResource(Res.string.invalid_password)
    SignInError.NetworkUnavailable -> stringResource(Res.string.network_unavailable)
    null -> null
  }

  errorMessage?.let { Text(it) }
}
```

Now the composable has to know every domain-specific error just to render text. If that error appears on another screen, the mapping gets duplicated. If the copy changes, the UI layer has to be touched. If a feature adds a new error, unrelated UI code may need to learn about it.

This is the wrong boundary.

## Domain models are not UI copy

Strongly typed domain and presentation models are still valuable. They give the view model something precise to reason about:

```kotlin
sealed interface SignInError {
  data object InvalidEmail : SignInError
  data object InvalidPassword : SignInError
  data object NetworkUnavailable : SignInError
}
```

Inside the view model, this is exactly the kind of thing I want. The view model can decide whether an error should block submission, whether it should be logged, whether retry is allowed, or whether it should be replaced by another state.

But once the view model publishes its state to the UI, the UI usually does not need `SignInError`. It needs displayable text.

That is where [`TextData`](https://github.com/Plus-Mobile-Apps/chef-mate/blob/main/client/text/public/src/commonMain/kotlin/com/plusmobileapps/chefmate/text/TextData.kt) comes in.

## What is TextData?

`TextData` is a small sealed model that represents text before it is resolved by Compose:

```kotlin
sealed class TextData {
  @Composable abstract fun localized(): String
}
```

Chef Mate currently has a few implementations:

```kotlin
data class FixedString(val value: String) : TextData()

data class ResourceString(
  val resource: StringResource,
) : TextData()

data class PhraseModel(
  val resource: StringResource,
  val args: Map<String, TextData> = emptyMap(),
) : TextData()

data class PluralResourceString(
  val resource: PluralStringResource,
  val quantity: Int,
  val args: Map<String, TextData> = emptyMap(),
) : TextData()
```

There is also `JoinedTextData` for joining a list of text parts at composition time.

The important part is not the specific set of subclasses. The important part is the direction of the dependency: shared presentation code can describe what text should be shown, while Compose UI remains responsible for resolving that text in a composable context.

## Map before exposing state

The pattern is to keep the strongly typed error internally and map it before exposing the public UI model.

```kotlin
private fun SignInError.toTextData(): TextData =
  when (this) {
    SignInError.InvalidEmail -> ResourceString(Res.string.invalid_email)
    SignInError.InvalidPassword -> ResourceString(Res.string.invalid_password)
    SignInError.NetworkUnavailable -> ResourceString(Res.string.network_unavailable)
  }
```

Then expose `TextData` from the state that the UI collects:

```kotlin
data class State(
  val email: String = "",
  val password: String = "",
  val errorMessage: TextData? = null,
)
```

The view model can still do its real work with meaningful types:

```kotlin
private fun onSignInFailed(error: SignInError) {
  mutableState.update { state ->
    state.copy(errorMessage = error.toTextData())
  }
}
```

Then the composable becomes boring in the best way:

```kotlin
@Composable
fun SignInScreen(state: State) {
  state.errorMessage?.let { error ->
    Text(text = error.localized())
  }
}
```

No domain error mapping. No feature-specific branching. No copy decisions hiding in UI layout code.

## Why this boundary feels better

This keeps the view model as the place where feature meaning gets translated into user-facing state. The UI receives a model that is already shaped for rendering.

That makes a few things nicer:

- UI code does not need to import domain-specific error types.
- Error-to-copy mapping is centralized and easier to test.
- Reused messages can be shared without duplicating `when` statements.
- Preview and fake states can provide `FixedString` when that is simpler.
- Resource-backed strings, phrases, plurals, and joined text can all move through the same public state model.

It also avoids leaking Compose resource APIs too deep into your state. The view model can hold `TextData`, but it does not have to call `stringResource()`. Actual localization still happens in composition through `localized()`.

## Phrases and plurals

The reason I prefer a text model over a plain resource id is that real UI text often has structure.

For example, a phrase can contain another piece of `TextData`:

```kotlin
PhraseModel(
  resource = Res.string.recipe_deleted,
  "name" to FixedString(recipeName),
)
```

A plural can carry both its quantity and placeholder values:

```kotlin
PluralResourceString(
  resource = Res.plurals.selected_recipe_count,
  quantity = selectedCount,
  "quantity" to FixedString(selectedCount.toString()),
)
```

That means the public UI state can still expose one property:

```kotlin
data class State(
  val selectionMessage: TextData,
)
```

The composable does not care whether that message is a fixed string, a resource string, a phrase, or a plural. It only cares that it can call `localized()`.

## Previews stay simple

Another nice side effect is that Compose previews do not need to recreate the exact production text model. The screen only depends on `TextData`, so preview code can use the simplest possible implementation.

```kotlin
@Preview
@Composable
fun RecipeDeletedPreview() {
  RecipeScreen(
    state = State(
      selectionMessage = FixedString("Chocolate cake was deleted"),
    ),
  )
}
```

In production, that same property might come from a much more complicated model:

```kotlin
PhraseModel(
  resource = Res.string.recipe_deleted_from_collection,
  "recipeName" to FixedString(recipe.name),
  "collectionName" to ResourceString(collection.displayName),
)
```

The preview does not care. It is trying to show layout, spacing, color, wrapping, and general screen state. A `FixedString` is often enough for that. Meanwhile, production code can still use a resource-backed phrase with nested `TextData` values and localization support.

That makes previews cheaper to write without weakening the real UI contract. The property is still `TextData`; the preview just chooses the easiest `TextData` for the job.

## The rule of thumb

Use strongly typed models for decisions.

Use `TextData` for display.

The view model can know that the sign-in attempt failed because of `InvalidEmail`. The UI should know that there is an `errorMessage` to render. Keeping those concerns separate gives the domain side better types and gives the UI side a smaller, more stable API.

That is the boundary I want in a KMP app: feature logic stays meaningful, localization stays composable, and screens stay focused on layout instead of becoming translation tables.
