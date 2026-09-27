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
| `static/`         | copied verbatim: `style.css` and the Pages `CNAME`      |
| `.github/`        | `deploy.yml`, builds and publishes the site on push     |

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

`deploy` is the branch that goes live. Push to it and the workflow builds the
site with the same nix derivation as `nix build`, then hands it to GitHub Pages.
`main` is the scratch branch and is never served.

```console
$ git switch deploy
$ nix run .        # preview at http://localhost:1111 first
$ git push origin deploy
```

The site is published at <https://blog.rozy.my.id>. Two settings have to agree
for that to work: `base_url` in `config.toml` and the Pages custom domain for
this repository. Change one, change the other. `static/CNAME` carries the same
name into the build output.

`base_url` is what every generated URL derives from, so it has to be the real
address: the feed, the sitemap, and the links between pages all read from it.
`nix run .` overrides it with `http://localhost:1111`, so local previews keep
working without being edited first.

For a host other than Pages, `nix build` still leaves the rendered files in
`./result` and nothing server side:

```console
$ nix build
$ cp -r result/* /var/www/blog/
```
