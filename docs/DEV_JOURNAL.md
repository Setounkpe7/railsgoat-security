# Development journal

Dated log of technical decisions, deviations from the original plan, and
obstacles encountered. Feeds REPORT.md sections 4 (Challenges) and 9
(What I would do differently).

---

## 2026-04-23 — Phase 2: Runtime viability

**Context.** The plan was written under the assumption that upstream
OWASP/RailsGoat was still on Ruby 2.x / Rails 4-5, and that Phase 2 would
be a 5 → 7 migration (LTS Ruby 3.3 + Rails 7.1). On opening the snapshot
imported in Phase 1, the Gemfile already declared `rails "~> 8.0.0"`,
`ruby "3.4.1"`, `puma 6`, `sqlite3 2`. OWASP modernized RailsGoat between
the spec being written and the import.

**Decision: adapt the plan to the upstream reality.**

Three options were considered:

- *A — Follow the plan literally.* Downgrade to Ruby 3.3.5 + Rails 7.1.
  Anti-pattern: downgrading a supported runtime to an older one
  introduces back CVEs that have since been patched, for no engineering
  benefit. Rejected.
- *B — Adapt to the upstream stack.* Keep Ruby 3.4.1 + Rails 8.0, treat
  Tasks 2.2 (Gemfile bump) and 2.3 (Rails 5 → 7 config update) as
  no-ops, focus the runtime work on packaging and bootability.
  Rationale: faithful to the spec's intent ("minimum viable migration to
  boot on a supported runtime"), authentic story for the case study
  (assess actual state, then act), frees time for the real subject
  matter — the DevSecOps pipeline. **Chosen.**
- *C — Hybrid.* Pin Ruby 3.3.5 (slightly older, more mature) but keep
  Rails 8. Compromise without clear gain. Rejected.

**Concrete adjustments applied:**

- Reverted the premature `.ruby-version → 3.3.5` commit; aligned to
  upstream 3.4.1.
- Tasks 2.2 and 2.3 collapsed to a single boot-fix commit covering only
  the gaps that prevented Rails 8 from booting on the upstream config:
    - `config/initializers/key.rb`: added an `ENV['RAILSGOAT_KEY']`
      fallback for the production environment. The original file only
      defined the `Encryption::KEY` constant in non-production, so any
      production boot died inside `db:seeds.rb` calling
      `User#generate_token`. The intentionally-insecure development
      hardcoded key is preserved untouched (it is the whole point of
      the training app).
    - `config/storage.yml`: created a minimal local Disk service.
      Active Storage in Rails 8 raises at boot if this file is missing.
    - `config/environments/production.rb`: removed the
      `js_compressor = :uglifier` line. The `uglifier` gem is
      unmaintained, was never declared in the Gemfile, and triggered a
      500 on the first asset render under sprockets.
- Task 2.4 (Dockerfile) implemented as specified, base image bumped
  from `ruby:3.3.5-slim-bookworm` to `ruby:3.4.1-slim-bookworm` to
  match the upstream Gemfile pin.

**Verification.** `docker build .` succeeds, `docker run` with
`SECRET_KEY_BASE` and `RAILSGOAT_KEY` environment variables returns
HTTP 200 on `/` and `/login`, container reports `healthy`. Same result
through `docker compose up`.

**Trade-offs accepted.**

- No upgrade attempted to Rails 8.1 / 8.2 — stability over bleeding
  edge, and we want to scan the version OWASP actually ships.
- SQLite kept as the production adapter (matches upstream
  `database.yml`); Postgres / MySQL gem groups are excluded from the
  production image via `BUNDLE_WITHOUT`.
- Ruby is not installed on the workstation. All Rails-side commands
  (bundle install, db:prepare, server) run inside the container
  during build or via `docker run`. Reproducibility benefit; small
  inner-loop friction cost.

**Obstacles encountered.**

- Three boot failures uncovered in sequence (Encryption::KEY missing →
  Active Storage config missing → uglifier not bundled). Each fix
  exposed the next layer; this is the typical pattern when running a
  legacy training app on a major Rails version it was not designed
  for.

**Time spent on phase 2.** ~1h30 (target was 3-4h; the upstream
modernization removed most of the originally-planned migration work).
