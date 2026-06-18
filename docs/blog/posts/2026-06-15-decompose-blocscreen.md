---
title: Letting a Decompose BLoC Render Itself
date: 2026-06-15
authors: [andrew]
categories:
  - Multiplatform
---

# Letting a Decompose BLoC Render Itself

![](../../assets/images/decompose-bloc-screen.png)

I use [Decompose](https://arkivanov.github.io/Decompose/) to manage navigation in my Kotlin Multiplatform projects. It does a great job of modeling navigation as a tree of business logic components (BLoCs) that are completely platform- and UI-agnostic. But that agnosticism comes with a small tax: something, somewhere, still has to decide which composable to draw for each BLoC. This post is about how I got rid of that boilerplate by giving each BLoC the ability to render itself since [Chef Mate](https://github.com/Plus-Mobile-Apps/chef-mate) uses Compose Multiplatform to render its UI. 

<!-- more -->

## The Problem

Decompose hands you a sealed `Child` hierarchy and a `Children`/`Child` slot to render. The library deliberately knows nothing about your UI, so the wiring between a `Child` variant and its composable lives in your render site as a `when` block:

```kotlin
Children(stack = bloc.routerState) { child ->
    when (val instance = child.instance) {
        is Child.CookMode -> CookModeScreen(instance.bloc)
        is Child.Detail   -> RecipeDetailScreen(instance.bloc)
        is Child.Edit     -> EditRecipeScreen(instance.bloc)
        // ...one arm per screen
    }
}
```

This exists purely to map a sealed variant to its composable. Every new screen means another arm, another import, and the same shape repeated across `RootScreen`, `RecipeRootScreen`, `BottomNavScreen`, and friends. It's the kind of boilerplate that isn't hard, just relentless.

## The Idea: an Interface for Rendering

Decompose keeps logic and UI apart on purpose, and I didn't want to throw that away. So instead of registering composables somewhere, I introduced a tiny interface in my `public` module that simply declares "I know how to render myself":

```kotlin
interface ComposeScreen {
    @Composable fun Content(modifier: Modifier)
}

@Composable fun ComposeScreen.Content() = Content(Modifier)
```

The key detail is *where* the implementation lives. The interface and its default body sit in the `public` API module, where the screen composable is already in scope. A BLoC's interface can supply the default rendering, while the `impl` module — the actual implementation detail — stays free of any Compose dependency:

```kotlin
interface CookModeBloc : ComposeScreen {
    // ...bloc state and intents...

    @Composable
    override fun Content(modifier: Modifier) {
        CookModeScreen(this, modifier)
    }
}
```

`CookModeBlocImpl` over in `cook/impl` doesn't change at all and gains no knowledge of Compose. The render site collapses to a single uniform call:

```kotlin
Children(stack = bloc.routerState) { child ->
    child.instance.bloc.Content()
}
```

No `when`. No per-screen imports. The BLoC owns the question "what do I look like?", which felt like the natural place for it to live. ([PR #198](https://github.com/Plus-Mobile-Apps/chef-mate/pull/198))

## Standardizing the Pattern

The prototype worked, so the [follow-up](https://github.com/Plus-Mobile-Apps/chef-mate/pull/304) rolled it out across every navigation `Child` in the app — root, recipe, meal planner, settings, AI chat, browser, bottom nav — plus the two `childSlot` sheet wrappers.

Along the way I settled on a slightly different shape than the original `BlocScreen by bloc` delegation. Instead, the `Child` sealed class declares the BLoC as an abstract property and each variant overrides it:

```kotlin
sealed class Child {
    abstract val bloc: ComposeScreen
    data class Detail(override val bloc: RecipeDetailBloc) : Child()
    data class Edit(override val bloc: EditRecipeBloc)     : Child()
}

// render:
Children(stack = bloc.routerState) { child ->
    child.instance.bloc.Content()
}
```

Reading the BLoC explicitly at the render site (`child.instance.bloc`) turned out to be clearer than interface delegation — you can see exactly what's being rendered, and not every `Child` variant is a screen anyway. For example, a `FullImage` variant that just carries `imageUrl`, `recipeId`, and `title` is plain data, not a BLoC, so it stays out of the pattern entirely.

## Takeaways

- **Decompose stays untouched.** This is a language-level interface, not a DI registry. The sealed `Configuration`/`Child` types and the lazy `childFactory` all work exactly as before.
- **The implementation module stays clean.** Because the default `Content()` lives in the `public` interface where the screen is already in scope, the `impl` modules never take on a Compose dependency.
- **Boilerplate moves to where it belongs.** Each BLoC answers "how do I render?" once, and every navigation parent gets a uniform, `when`-free render call for free.

Sometimes the cleanest way to bind a screen to its logic is to stop binding them at the call site at all — and let the component tell you.
