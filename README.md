# blog

Technical write ups, rendered by [zola](https://www.getzola.org/) and driven by a
nix flake. No javascript on the page, one CDN stylesheet, code highlighted at
build time.

## Layout

| path              | what it is                                            |
| ----------------- | ----------------------------------------------------- |
| `flake.nix`       | package, dev shell, `nix run` app, checks, formatter   |
| `build.nix`       | runs `zola build` and installs the rendered site        |
| `config.toml`     | title, `base_url`, atom feed, syntax highlighting theme |
| `content/`        | one markdown file per post                             |
| `templates/`      | `base.html`, `index.html` (home), `page.html` (post)   |
| `static/`         | copied verbatim, currently just `style.css`            |

## Commands

```console
$ nix run .        # dev server on http://localhost:1111, rebuilds on save
$ nix build        # renders the site into ./result
$ nix develop      # shell with zola on PATH
$ nix fmt          # formats flake.nix and build.nix
$ nix flake check  # builds every output on every supported system
```

## Writing a post

Create `content/<slug>.md`. Front matter needs a `title` and a `date`; `description`
is what shows up in the home page list and the feed.

```markdown
+++
title = "Porting NonEmpty to Koka with Nix"
date = 2026-09-27
description = "One line, used for the list entry and the feed."
+++

The title lives in the front matter, so the body starts here.
```

Posts are ordered newest first, and the home page lists them automatically.

## Publishing

`nix build` leaves the site in `./result`: plain files, no server side anything.
Copy them wherever you host it.

```console
$ nix build
$ cp -r result/* /var/www/blog/
```

Set `base_url` in `config.toml` to the real URL first. The feed, the sitemap, and
the links between pages are all derived from it; `nix run .` overrides it with
`http://localhost:1111` so local previews work unchanged.
