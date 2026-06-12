#!/usr/bin/env bash

set -euo pipefail

POSTS_DIR="${POSTS_DIR:-docs/blog/posts}"
DEFAULT_AUTHOR="${DEFAULT_AUTHOR:-andrew}"

trim() {
  local value="$*"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

yaml_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

prompt_required() {
  local label="$1"
  local value=""

  while [[ -z "$value" ]]; do
    read -r -p "$label: " value
    value="$(trim "$value")"
  done

  printf '%s' "$value"
}

prompt_optional() {
  local label="$1"
  local default_value="${2:-}"
  local value=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " value
    value="$(trim "$value")"
    printf '%s' "${value:-$default_value}"
  else
    read -r -p "$label: " value
    trim "$value"
  fi
}

write_yaml_list() {
  local label="$1"
  local csv="$2"
  local item=""
  local has_items=false

  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    if [[ -n "$item" ]]; then
      if [[ "$has_items" == false ]]; then
        printf '%s\n' "$label:"
        has_items=true
      fi
      printf "  - '%s'\n" "$(yaml_escape "$item")"
    fi
  done
}

today="$(date +%F)"

echo "New blog post"
echo "-------------"

title="$(prompt_required "Title")"
description="$(prompt_required "Description / blog preview text")"
date_value="$(prompt_optional "Publish date" "$today")"
author="$(prompt_optional "Author" "$DEFAULT_AUTHOR")"
categories="$(prompt_optional "Categories, comma-separated")"
tags="$(prompt_optional "Tags, comma-separated")"
slug_default="$(slugify "$title")"
slug="$(prompt_optional "URL/file slug" "$slug_default")"
heading="$(prompt_optional "H1 heading" "$title")"
image_path="$(prompt_optional "Image path relative to post, optional")"

if [[ ! "$date_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Publish date must use YYYY-MM-DD format." >&2
  exit 1
fi

if [[ -z "$slug" ]]; then
  echo "Slug cannot be empty." >&2
  exit 1
fi

mkdir -p "$POSTS_DIR"

post_path="$POSTS_DIR/$date_value-$slug.md"

if [[ -e "$post_path" ]]; then
  echo "Post already exists: $post_path" >&2
  exit 1
fi

{
  printf '%s\n' '---'
  printf "title: '%s'\n" "$(yaml_escape "$title")"
  printf 'date: %s\n' "$date_value"
  printf "authors: ['%s']\n" "$(yaml_escape "$author")"
  printf '%s\n' 'description: >'
  printf '  %s\n' "$description"
  write_yaml_list "categories" "$categories"
  write_yaml_list "tags" "$tags"
  printf '%s\n\n' '---'
  printf '# %s\n\n' "$heading"
  if [[ -n "$image_path" ]]; then
    printf '![](%s)\n\n' "$image_path"
  fi
  printf '%s\n\n' "$description"
  printf '%s\n\n' '<!-- more -->'
  printf '## TODO\n\n'
} > "$post_path"

echo "Created $post_path"
