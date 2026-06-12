# Plus Mobile Apps Website

## Creating a blog post

Run the interactive helper from the repository root:

```bash
./new-post.sh
```

The script prompts for:

- Title
- Description / blog preview text
- Publish date, defaulting to today
- Author, defaulting to `andrew`
- Categories, as a comma-separated list
- Tags, as a comma-separated list
- URL/file slug, defaulting to a slugified title
- H1 heading, defaulting to the title
- Optional image path relative to the generated post

It creates a new Markdown file in `docs/blog/posts` named with the
`YYYY-MM-DD-slug.md` pattern. The generated post includes MkDocs blog
frontmatter, the preview text, a `<!-- more -->` marker, and a `## TODO`
section to start drafting from.

The script exits without writing over an existing post.

### Optional overrides

Use `POSTS_DIR` to write posts somewhere else, which is useful for testing:

```bash
POSTS_DIR=/tmp/blog-posts ./new-post.sh
```

Use `DEFAULT_AUTHOR` to change the default author prompt:

```bash
DEFAULT_AUTHOR=your-name ./new-post.sh
```
