# WaveCrux user documentation

The source of **https://docs.wavecrux.app/** — the WaveCrux user guide, built
with [MkDocs](https://www.mkdocs.org/) and
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). This file
is not part of the built site.

## Preview and build

Use the same pinned versions CI uses (`.github/workflows/docs.yml`):

```bash
python3 -m venv .venv
.venv/bin/pip install mkdocs==1.6.0 mkdocs-material==9.5.27 \
  pymdown-extensions==10.9 Pygments==2.19.2
```

From this `docs-site/` directory:

```bash
../.venv/bin/mkdocs serve            # live preview at http://127.0.0.1:8000/
../.venv/bin/mkdocs build --strict   # what CI runs; any warning fails the build
```

(Adjust the path to wherever you created the virtual environment.) The build
writes to `site/`, which is git-ignored.

## Deployment

CI builds every pull request that touches `docs-site/` and, on merge to
`main`, deploys the built `site/` to Cloudflare Workers Static Assets
(`wrangler.jsonc`, route `docs.wavecrux.app`). Nothing is deployed by hand.

## Conventions

- **One page per slug.** Each page is `docs/<slug>.md` and is served
  extensionless at `https://docs.wavecrux.app/<slug>` (`use_directory_urls:
  false`). Slugs are public URLs — the app's in-product help links and the
  redirects from `wavecrux.app/docs/<slug>` depend on them, so do not rename or
  remove a page, or an explicit heading anchor (`{ #anchor }`), without
  updating those links.
- **Links between pages** are relative `.md` links (`[Stage](stage.md#playback)`);
  strict mode checks them. Marketing pages link absolutely to
  `https://wavecrux.app/<page>`, suite pages to `https://edacrux.app/<page>`.
- **Tier badges** go after the heading or feature name, exactly as
  `<span class="tier tier-pro">Pro</span>`,
  `<span class="tier tier-enterprise">Enterprise</span>` or
  `<span class="tier tier-edu">EDU</span>`. Anything without a badge is Open
  Core. The styles live in `docs/assets/brand.css`.
- **UI labels** are written exactly as the app shows them (bold), taken from
  the English ARB file and the widgets, and keyboard shortcuts use
  `++cmd+shift+p++ / ++ctrl+shift+p++`, macOS first.
- **Behaviour that does not work yet** is marked with a
  `!!! warning "Known issue"` box rather than described as working.
- **Behaviour changes update these pages in the same pull request** as the
  code change, the same way they update the verification guide.
