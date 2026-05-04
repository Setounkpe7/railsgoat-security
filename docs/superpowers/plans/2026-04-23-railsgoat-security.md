# railsgoat-security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take a snapshot of OWASP/RailsGoat, migrate it to a supported Ruby runtime, wrap it in a full DevSecOps pipeline (secrets, SAST, SCA, DAST, SBOM, image signing), remediate critical/high findings, document residual medium/low findings, and publish as a portfolio case study at `github.com/Setounkpe7/railsgoat-security`.

**Architecture:** Fresh GitHub repo with attribution-preserving snapshot import. Working branch `dev`, protected `main`. Two GitHub Actions workflows: `security.yml` (on PR → main, 8 security jobs, produces SARIF + SBOM + signed image on GHCR) and `auto-pr.yml` (on push → dev, creates/updates PR dev → main). Local mirror of the pipeline via `scripts/scan-all.sh` for local-first validation. Remediation follows gating policy D: per-tool severity thresholds, residual risk formally accepted in `SECURITY_EXCEPTIONS.md`.

**Tech Stack:** Ruby 3.3 + Rails 7.1 (minimum viable migration), Docker multi-stage, GitHub Actions, detect-secrets, Brakeman, Semgrep, bundler-audit, Trivy (fs + image + config), Hadolint, OWASP ZAP baseline, Syft (CycloneDX), Grype, Cosign keyless OIDC, Dependabot, pre-commit framework, `peter-evans/create-pull-request`, `gh` CLI.

**Spec source:** [../specs/2026-04-23-railsgoat-security-design.md](../specs/2026-04-23-railsgoat-security-design.md)

---

## File structure overview

All paths relative to `/home/mdoub/Github/railsgoat-security/` unless noted.

**Repository configuration files (root)**
- `.gitignore` — exclude Rails runtime artifacts, secrets, caches, OS/IDE droppings. **Not** scan reports.
- `.dockerignore` — mirror of gitignore scoped to Docker build context
- `.gitattributes` — enforce LF line endings on YAML/Ruby
- `.ruby-version` — pin Ruby 3.3 for rbenv/asdf users
- `Dockerfile` — multi-stage: build → runtime, non-root, pinned base image
- `docker-compose.yml` — local Postgres + Rails for dev only

**Tool configs (root, discoverable)**
- `.pre-commit-config.yaml` — pre-commit hooks orchestration
- `.secrets.baseline` — detect-secrets accepted findings
- `.brakeman.ignore` — Brakeman accepted findings (JSON)
- `.semgrepignore` — path exclusions for Semgrep
- `.trivyignore` — CVE exceptions with expiry dates
- `.hadolint.yaml` — Dockerfile lint policy

**Attribution and risk (root)**
- `LICENSE` — MIT, inherited from upstream, do not modify
- `CREDITS.md` — OWASP upstream attribution
- `NOTICE.md` — legal notice
- `SECURITY_EXCEPTIONS.md` — accepted medium/low findings register

**Narrative (root + docs/)**
- `README.md` — concise project intro and repo navigation
- `REPORT.md` — portfolio case study (10 sections)
- `docs/DEV_JOURNAL.md` — dated technical decisions log
- `docs/ARCHITECTURE.md` — pipeline diagram, branch + PR flow
- `docs/RUNBOOK.md` — reproduction guide for reviewer

**CI workflows (.github/workflows/)**
- `security.yml` — main DevSecOps pipeline (triggered on PR → main)
- `auto-pr.yml` — creates/updates PR dev → main on push to dev

**Local reproduction (scripts/)**
- `scan-all.sh` — full local pipeline orchestrator
- `scan-secrets.sh`, `scan-sast.sh`, `scan-sca.sh`, `scan-image.sh`, `scan-dast.sh` — per-layer scripts
- `generate-sbom.sh` — Syft + Grype local run
- `setup-branch-protection.sh` — applies branch protection via `gh api`

**Committed scan outputs (docs/scan-reports/)**
- Baseline (post-phase 3) and final (post-phase 4) copies of each tool's report

**Application code (inherited from RailsGoat)**
- `app/`, `config/`, `db/`, `lib/`, `public/`, `spec/`, `Gemfile`, `Gemfile.lock`, `Rakefile`, `config.ru`

---

# Phase 1 — Bootstrap (target: ~1h)

**Outcome:** Repo exists on GitHub with snapshot + attribution + protected main + working dev branch.

---

### Task 1.1: Prepare local workspace and clone upstream snapshot

**Files:**
- Create: `/home/mdoub/Github/_railsgoat-upstream/` (temporary, deleted at end of phase)

- [ ] **Step 1: Verify working directory and tool availability**

Run:
```bash
cd /home/mdoub/Github
which gh git rsync
gh auth status
```

Expected: `/usr/bin/gh` (or equivalent), `git`, `rsync` resolve. `gh auth status` shows logged in as `Setounkpe7`. If not, stop and run `gh auth login`.

- [ ] **Step 2: Shallow-clone RailsGoat upstream**

Run:
```bash
cd /home/mdoub/Github
git clone --depth 1 https://github.com/OWASP/railsgoat.git _railsgoat-upstream
```

Expected: new folder `_railsgoat-upstream/` exists.

- [ ] **Step 3: Capture upstream HEAD SHA for provenance**

Run:
```bash
cd /home/mdoub/Github/_railsgoat-upstream
UPSTREAM_SHA=$(git rev-parse HEAD)
echo "UPSTREAM_SHA=$UPSTREAM_SHA" > /tmp/railsgoat_upstream_sha
cat /tmp/railsgoat_upstream_sha
```

Expected: a 40-character SHA echoed. Keep this file, it's used in Task 1.3.

- [ ] **Step 4: Discard upstream git history**

Run:
```bash
rm -rf /home/mdoub/Github/_railsgoat-upstream/.git
ls -la /home/mdoub/Github/_railsgoat-upstream/.git 2>&1
```

Expected: `No such file or directory`.

---

### Task 1.2: Create target repo on GitHub and clone it

**Files:**
- Create: `/home/mdoub/Github/railsgoat-security/` (fresh git repo)

- [ ] **Step 1: Create the repo on GitHub via `gh`**

Run:
```bash
cd /home/mdoub/Github
gh repo create Setounkpe7/railsgoat-security \
  --public \
  --description "DevSecOps hardening of OWASP RailsGoat — SAST, SCA, secrets, SBOM, DAST pipeline" \
  --clone \
  --add-readme=false
```

Expected: folder `railsgoat-security/` created, contains only `.git/`. Remote `origin` set to `https://github.com/Setounkpe7/railsgoat-security.git`.

- [ ] **Step 2: Verify remote and initial state**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git remote -v
git branch -a
```

Expected: remote `origin` points to `Setounkpe7/railsgoat-security`. No branches yet (repo is empty).

---

### Task 1.3: Import snapshot as first commit on main

**Files:**
- Copy all of `_railsgoat-upstream/*` (except `.github/`) into `railsgoat-security/`

- [ ] **Step 1: Copy snapshot, excluding upstream CI**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
rsync -a --exclude='.github/' ../_railsgoat-upstream/ .
ls -la
```

Expected: Rails app structure visible (`app/`, `config/`, `Gemfile`, etc.), no `.github/` folder.

- [ ] **Step 2: Verify LICENSE is present and MIT**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
head -3 LICENSE
```

Expected: first line contains "MIT License". If not, `ls *LICENSE*` to locate — RailsGoat must have one, MIT requires preserving it.

- [ ] **Step 3: Configure git identity if not already global**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git config user.name
git config user.email
```

Expected: name and email set. If empty, run `git config user.name "<name>"` and `git config user.email "Mdoubogan@yahoo.fr"` in this repo.

- [ ] **Step 4: First commit — snapshot**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
source /tmp/railsgoat_upstream_sha
git add .
git commit -m "chore: import OWASP/railsgoat snapshot

Source: https://github.com/OWASP/railsgoat
Upstream commit: ${UPSTREAM_SHA}
License: MIT (preserved in LICENSE)
Date of import: $(date -I)

This is an unmodified snapshot imported for DevSecOps hardening.
All subsequent commits are my own work."
```

Expected: commit created. Run `git log --oneline` and see one commit.

---

### Task 1.4: Add attribution files (CREDITS, NOTICE) as second commit

**Files:**
- Create: `CREDITS.md`
- Create: `NOTICE.md`

- [ ] **Step 1: Write `CREDITS.md`**

Create `/home/mdoub/Github/railsgoat-security/CREDITS.md` with:

```markdown
# Credits

This project is a DevSecOps hardening exercise built on top of
[OWASP RailsGoat](https://github.com/OWASP/railsgoat), an intentionally
vulnerable Ruby on Rails application maintained by the OWASP Foundation.

## Original work
- **Project:** OWASP RailsGoat
- **Authors:** Ken Johnson, Mike McCabe, Lance Talbert, and OWASP contributors
  (see upstream git history)
- **License:** MIT
- **Upstream:** https://github.com/OWASP/railsgoat
- **Imported snapshot:** commit `<UPSTREAM_SHA>`, imported on `<DATE>`

## This repository
All DevSecOps tooling, pipeline configuration, containerization,
vulnerability remediation, and documentation added after the initial
import commit are my own work, released under the same MIT license.
```

Replace `<UPSTREAM_SHA>` and `<DATE>` with the values from `/tmp/railsgoat_upstream_sha` and `date -I`.

- [ ] **Step 2: Write `NOTICE.md`**

Create `/home/mdoub/Github/railsgoat-security/NOTICE.md` with:

```markdown
# Notice

Portions of this repository are derived from OWASP RailsGoat
(Copyright © The OWASP Foundation), distributed under the MIT License.
The original copyright notice is preserved in LICENSE.

See CREDITS.md for full attribution.
```

- [ ] **Step 3: Commit attribution**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add CREDITS.md NOTICE.md
git commit -m "docs: add attribution and notice for upstream OWASP/railsgoat"
```

Expected: `git log --oneline` shows 2 commits.

---

### Task 1.5: Add `.gitignore` as third commit

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

Create `/home/mdoub/Github/railsgoat-security/.gitignore` with:

```gitignore
# === Rails / Ruby runtime artifacts ===
/log/*
!/log/.keep
/tmp/*
!/tmp/.keep
/storage/*
!/storage/.keep
/public/assets
/vendor/bundle
/.bundle
.byebug_history
.rspec_status
coverage/

# === Local databases ===
/db/*.sqlite3
/db/*.sqlite3-journal

# === Secrets (NEVER commit) ===
.env
.env.*
!.env.example
/config/master.key
/config/credentials/*.key

# === Node (if asset pipeline touches JS) ===
node_modules/
yarn-error.log
yarn-debug.log*
npm-debug.log*

# === Tool caches ===
.brakeman/
.semgrep/
.trivy/
.bundler-audit/
.cache/

# === IDE / OS ===
.idea/
.vscode/
.DS_Store
Thumbs.db
*.swp
*.swo
*~

# === Temporary work artifacts ===
_railsgoat-upstream/
*.bak
*.orig
*.rej

# NOTE: scan reports are deliberately NOT ignored — they are committed
# to docs/scan-reports/ as part of the portfolio deliverable.
```

- [ ] **Step 2: Commit gitignore**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .gitignore
git commit -m "chore: add .gitignore for Rails + security tooling discipline"
```

Expected: 3 commits total.

---

### Task 1.6: Push main and create protected `dev` branch

- [ ] **Step 1: Push main to origin**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push -u origin main
```

Expected: `main` pushed to `origin`.

- [ ] **Step 2: Create and push dev branch**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git checkout -b dev
git push -u origin dev
```

Expected: `dev` branch exists on origin. `git branch -a` shows `main`, `dev`, `origin/main`, `origin/dev`.

---

### Task 1.7: Apply branch protection on `main`

**Files:**
- Create: `scripts/setup-branch-protection.sh`

- [ ] **Step 1: Write `scripts/setup-branch-protection.sh`**

Create `/home/mdoub/Github/railsgoat-security/scripts/setup-branch-protection.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Applies branch protection on main. Idempotent — safe to re-run.
# Run from repo root. Requires `gh` authenticated with repo-admin scope.

OWNER="Setounkpe7"
REPO="railsgoat-security"

# The status checks list will be populated once CI job names exist.
# For phase 1 we apply structural protections only; required checks
# are added in Task 5.7 after security.yml lands on main.

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${REPO}/branches/main/protection" \
  -f "required_status_checks=null" \
  -F "enforce_admins=true" \
  -f "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  -f "required_pull_request_reviews[require_code_owner_reviews]=false" \
  -F "required_pull_request_reviews[required_approving_review_count]=0" \
  -f "restrictions=null" \
  -F "allow_force_pushes=false" \
  -F "allow_deletions=false" \
  -F "required_conversation_resolution=true" \
  -F "lock_branch=false" \
  -F "allow_fork_syncing=false"

echo "Branch protection applied on main."
```

Make executable:
```bash
chmod +x /home/mdoub/Github/railsgoat-security/scripts/setup-branch-protection.sh
```

- [ ] **Step 2: Run branch protection script**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
./scripts/setup-branch-protection.sh
```

Expected: output ends with `Branch protection applied on main.` No HTTP error from `gh`.

- [ ] **Step 3: Verify branch protection is active**

Run:
```bash
gh api /repos/Setounkpe7/railsgoat-security/branches/main/protection | jq '{approvals: .required_pull_request_reviews.required_approving_review_count, force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}'
```

Expected:
```json
{"approvals": 0, "force_push": false, "deletions": false}
```

- [ ] **Step 4: Commit the script on dev**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git checkout dev
git add scripts/setup-branch-protection.sh
git commit -m "chore: add branch protection setup script"
git push origin dev
```

Expected: script committed on dev (not main — main should only receive PRs from here on).

---

### Task 1.8: Clean up temporary upstream directory

- [ ] **Step 1: Remove temp upstream**

Run:
```bash
rm -rf /home/mdoub/Github/_railsgoat-upstream
rm -f /tmp/railsgoat_upstream_sha
```

Expected: directory and temp SHA file gone.

**✅ Phase 1 checkpoint:**
- `Setounkpe7/railsgoat-security` exists, public, 3 commits on main, 4 commits on dev
- `main` protected (0 approvals, no force push, no deletion)
- `dev` tracks origin
- Working tree clean: `git status` → nothing to commit

---

# Phase 2 — Runtime viable (target: ~3-4h)

**Outcome:** The app boots on Ruby 3.3 + Rails 7.1 (or Rails 6.1 fallback), a Dockerfile produces a runnable image, `docker run` returns HTTP 200 on `/`.

**Branch:** all work on `dev`.

---

### Task 2.1: Pin Ruby version

**Files:**
- Create: `.ruby-version`

- [ ] **Step 1: Write `.ruby-version`**

Create `/home/mdoub/Github/railsgoat-security/.ruby-version` with:

```
3.3.5
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .ruby-version
git commit -m "chore: pin Ruby 3.3.5"
```

---

### Task 2.2: Bump Gemfile to Rails 7.1

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Read current Gemfile**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
cat Gemfile
```

Expected: Gemfile specifying `rails` at some 4.x or 5.x version. Note the full contents.

- [ ] **Step 2: Update `ruby` and `rails` lines**

Edit the top of `Gemfile`:

Replace the line starting with `ruby` (any form) with:
```ruby
ruby "3.3.5"
```

Replace the line starting with `gem "rails"` with:
```ruby
gem "rails", "~> 7.1.0"
```

If the Gemfile specifies `sqlite3`, ensure:
```ruby
gem "sqlite3", "~> 1.7"
```

- [ ] **Step 3: Comment out gems known to be incompatible with Rails 7**

Common incompatibilities in RailsGoat:
- `protected_attributes` (obsolete, replaced by strong_parameters) → remove
- `rails_12factor` → remove (not needed in Rails 7)
- `quiet_assets` → remove (built into Rails)
- `sass-rails` (old major) → bump to `~> 6.0`
- `coffee-rails` → remove if present
- `therubyracer` → remove (replaced by Node)

For each, delete the line rather than comment — keep the Gemfile clean.

- [ ] **Step 4: Delete stale Gemfile.lock**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
rm Gemfile.lock
```

Rationale: let Bundler re-resolve against Ruby 3.3 + Rails 7.1 from scratch.

- [ ] **Step 5: Install fresh Gemfile.lock**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
bundle install 2>&1 | tee /tmp/bundle-install.log
```

Expected: resolution succeeds. If errors, note the offending gem and either bump or remove it.

**Fallback trigger:** if after 2 passes of bumping gems, resolution still fails → downgrade Rails to 6.1 in Gemfile (`gem "rails", "~> 6.1.0"`) and re-try. Log the decision in `docs/DEV_JOURNAL.md` (created in Task 2.7).

- [ ] **Step 6: Commit Gemfile + Gemfile.lock**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add Gemfile Gemfile.lock
git commit -m "chore: migrate Gemfile to Ruby 3.3 + Rails 7.1"
```

---

### Task 2.3: Rails config updates required by 5 → 7

**Files:**
- Modify: `config/application.rb`, `config/environments/development.rb`, `config/environments/production.rb`, `config/environments/test.rb`
- Create: `config/credentials.yml.enc` + `config/master.key` (via rails command)
- Delete: `config/secrets.yml` (replaced by credentials)

- [ ] **Step 1: Run `rails app:update` interactively**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
bin/rails app:update 2>&1 | tee /tmp/rails-app-update.log
```

For each prompt, answer `n` (no overwrite) unless the file is a new config file that didn't exist (answer `Y` for those). Goal: minimize changes, just let Rails add new required config files.

- [ ] **Step 2: Generate credentials file**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
EDITOR=true bin/rails credentials:edit
```

Expected: `config/credentials.yml.enc` and `config/master.key` created. `master.key` is gitignored (already covered).

- [ ] **Step 3: Remove legacy `config/secrets.yml`**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
rm -f config/secrets.yml
```

- [ ] **Step 4: Update `config/application.rb` to load Rails 7 defaults**

Edit `config/application.rb`. The line `config.load_defaults X.Y` should read:
```ruby
config.load_defaults 7.1
```

If the current value is lower (5.x or 6.x), update it. Keep any custom lines untouched.

- [ ] **Step 5: Attempt to boot the app**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
bin/rails runner "puts 'Rails boots on ' + Rails.version" 2>&1 | tee /tmp/rails-boot.log
```

Expected: last line is `Rails boots on 7.1.x`. If errors, read the last ~20 lines of the log, fix the offending config/require/class, re-run.

Common errors and fixes:
- `uninitialized constant XYZ` → the class is in `app/` and needs Zeitwerk-compatible naming (file `foo_bar.rb` → class `FooBar`)
- `NameError: uninitialized constant Rails::Application::Configuration::...` → remove `config.active_record.legacy_connection_handling` or similar retired settings
- `RuntimeError: Missing secret_key_base` → add `bin/rails credentials:edit` again and set `secret_key_base: <64-char-hex>`

- [ ] **Step 6: Run DB migrations**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
bin/rails db:setup 2>&1 | tee /tmp/rails-db-setup.log
```

Expected: migrations run, seed data loaded (if `db/seeds.rb` exists).

If a migration fails because it uses Rails 4-era syntax (e.g., `t.change`), edit the migration to use `Rails 7`-compatible syntax. Prefer deleting and re-creating seed-only data rather than preserving ancient migration quirks.

- [ ] **Step 7: Commit config changes**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add config/ bin/ Gemfile.lock
git rm -f config/secrets.yml 2>/dev/null || true
git commit -m "chore: Rails 7.1 config update (credentials, load_defaults, strong_parameters)"
```

---

### Task 2.4: Write `Dockerfile` (multi-stage, non-root)

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`

- [ ] **Step 1: Write `.dockerignore`**

Create `/home/mdoub/Github/railsgoat-security/.dockerignore` with:

```
.git
.github
.gitignore
.gitattributes
README.md
REPORT.md
CREDITS.md
NOTICE.md
SECURITY_EXCEPTIONS.md
docs/
scripts/
.brakeman.ignore
.semgrepignore
.trivyignore
.secrets.baseline
.pre-commit-config.yaml
.hadolint.yaml
log/*
tmp/*
storage/*
node_modules/
coverage/
*.md
```

- [ ] **Step 2: Write `Dockerfile`**

Create `/home/mdoub/Github/railsgoat-security/Dockerfile` with:

```dockerfile
# syntax=docker/dockerfile:1.7

# ===== Build stage =====
FROM ruby:3.3.5-slim-bookworm AS build

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      curl \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf /usr/local/bundle/cache/*.gem && \
    find /usr/local/bundle -name "*.c" -delete && \
    find /usr/local/bundle -name "*.o" -delete

COPY . .

RUN SECRET_KEY_BASE=dummy bundle exec bootsnap precompile --gemfile app/ lib/ config/ 2>/dev/null || true

# ===== Runtime stage =====
FROM ruby:3.3.5-slim-bookworm AS runtime

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libsqlite3-0 \
      libpq5 \
      libyaml-0-2 \
      curl \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1000 app && \
    useradd app --uid 1000 --gid 1000 --create-home --shell /bin/bash

WORKDIR /app

COPY --from=build --chown=app:app /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=app:app /app /app

USER app:app

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD curl -fsS http://localhost:3000/ || exit 1

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

- [ ] **Step 3: Build image locally**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
docker build -t railsgoat-security:local . 2>&1 | tee /tmp/docker-build.log
```

Expected: build succeeds, final line is `naming to docker.io/library/railsgoat-security:local`.

- [ ] **Step 4: Run container and verify HTTP 200**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
SECRET_KEY_BASE=$(bin/rails secret)
docker run --rm -d -p 3000:3000 \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e RAILS_ENV=production \
  --name rg-test \
  railsgoat-security:local
sleep 15
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/
docker stop rg-test
```

Expected: final curl output `200`. If 500 or connection refused, inspect logs with `docker logs rg-test` before stopping, find root cause, fix, rebuild.

Common causes: missing `SECRET_KEY_BASE` (set as env), static assets not precompiled (add `RUN bundle exec rails assets:precompile` step in Dockerfile before COPY . .), database not migrated (Rails needs an init step — add a `docker-entrypoint.sh` that runs `rails db:prepare` before server start).

- [ ] **Step 5: Commit Dockerfile**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add Dockerfile .dockerignore
git commit -m "feat: multi-stage Dockerfile for Rails 7.1, non-root, healthcheck"
```

---

### Task 2.5: Write `docker-compose.yml` for local dev

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Write `docker-compose.yml`**

Create `/home/mdoub/Github/railsgoat-security/docker-compose.yml` with:

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: railsgoat-security:local
    environment:
      RAILS_ENV: production
      RAILS_LOG_TO_STDOUT: "1"
      RAILS_SERVE_STATIC_FILES: "1"
      SECRET_KEY_BASE: "${SECRET_KEY_BASE:?run: export SECRET_KEY_BASE=\$(bin/rails secret)}"
    ports:
      - "3000:3000"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:3000/"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 20s
```

- [ ] **Step 2: Verify compose up**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
export SECRET_KEY_BASE=$(bin/rails secret)
docker compose up -d
sleep 20
docker compose ps
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/
docker compose down
```

Expected: curl returns `200`, compose down cleans up.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docker-compose.yml
git commit -m "chore: add docker-compose for local dev"
```

---

### Task 2.6: Invoke `simplify` skill on migration work

- [ ] **Step 1: Run simplify on phase 2 changes**

From the current session or a new one, invoke:
```
/simplify
```

Scope: review the diff since the start of phase 2 (commits after branch protection setup) — specifically Gemfile, Dockerfile, docker-compose.yml, config changes.

Expected: either no suggestions, or small cleanup commits that don't change behavior.

---

### Task 2.7: Create `DEV_JOURNAL.md` and log phase 2

**Files:**
- Create: `docs/DEV_JOURNAL.md`

- [ ] **Step 1: Write `docs/DEV_JOURNAL.md`**

Create `/home/mdoub/Github/railsgoat-security/docs/DEV_JOURNAL.md` with:

```markdown
# Development journal

Dated log of technical decisions and obstacles. Feeds REPORT.md sections
4 (Challenges) and 9 (What I would do differently).

---

## 2026-04-23 — Phase 2: Runtime migration

**Context:** RailsGoat upstream is on Ruby 2.x / Rails 4-5. Target: minimum
viable migration to a supported Ruby runtime so that the app boots, without
rewriting vulnerable business logic (that is the whole point of the project).

**Decisions:**
- Ruby 3.3.5 (current stable 3.3.x, supported until 2027)
- Rails 7.1 (LTS as of 2026, compatible with Ruby 3.3)
- Regenerated Gemfile.lock from scratch rather than bundle update
- Switched to credentials.yml.enc (Rails 5.2+ standard), removed secrets.yml
- Dockerfile uses slim-bookworm for smaller attack surface
- Non-root user in container (uid 1000)
- Healthcheck at /

**Obstacles encountered:**
(filled in during actual work)

**Trade-offs accepted:**
- Did not upgrade to Rails 7.2 or 8.x — stability over bleeding edge
- Did not switch to Postgres — keeping sqlite for simplicity in CI

**Time spent:** X hours (to be filled at end of phase)
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/DEV_JOURNAL.md
git commit -m "docs: add DEV_JOURNAL for dated technical decisions"
```

---

### Task 2.8: Push dev and verify auto-PR does not yet exist

- [ ] **Step 1: Push dev**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push origin dev
```

- [ ] **Step 2: Confirm no PR opens automatically yet**

Run:
```bash
gh pr list --repo Setounkpe7/railsgoat-security
```

Expected: empty list. The auto-PR workflow is created in Phase 5 — for now, we do NOT want a PR opening until the pipeline is ready to gate it.

**✅ Phase 2 checkpoint:**
- `docker build . && docker run` → HTTP 200 on `/`
- `docker compose up -d` works
- Git log shows ~7-10 clean commits on dev
- DEV_JOURNAL has the phase 2 entry

---

# Phase 3 — Security tooling local (target: ~2h)

**Outcome:** detect-secrets, Brakeman, Semgrep, bundler-audit, Trivy, Hadolint, Syft, Grype, ZAP all installed and baseline-scanned locally. Baseline findings committed. Initial triage of critical/high vs medium/low documented.

**Branch:** all work on `dev`.

---

### Task 3.1: Install required CLIs locally

- [ ] **Step 1: Verify/install tool binaries**

Run:
```bash
which detect-secrets pre-commit brakeman semgrep bundle-audit trivy hadolint syft grype cosign 2>&1
docker --version
```

For each missing binary, install:
- `detect-secrets`: `pipx install detect-secrets` (or `pip install --user`)
- `pre-commit`: `pipx install pre-commit`
- `brakeman`: `gem install brakeman` (or via Gemfile dev group)
- `semgrep`: `pipx install semgrep`
- `bundle-audit`: `gem install bundler-audit`
- `trivy`: download from https://github.com/aquasecurity/trivy/releases (binary to `~/.local/bin/`)
- `hadolint`: download from https://github.com/hadolint/hadolint/releases
- `syft`, `grype`: `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b ~/.local/bin/` and same for grype
- `cosign`: download from https://github.com/sigstore/cosign/releases

Expected: all binaries resolve with `which`. If any refuses to install, note it and fall back to Docker-packaged versions for CI-only use (local runs will use `docker run aquasec/trivy` etc.).

---

### Task 3.2: Initialize detect-secrets baseline

**Files:**
- Create: `.secrets.baseline`

- [ ] **Step 1: Generate baseline**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
detect-secrets scan --all-files \
  --exclude-files '\.git/|docs/scan-reports/|vendor/|node_modules/' \
  > .secrets.baseline
head -30 .secrets.baseline
```

Expected: JSON file with `plugins_used`, `results`, `generated_at`. `results` may be non-empty (RailsGoat has hardcoded creds — we want them baselined so we detect *new* secrets only).

- [ ] **Step 2: Commit baseline**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .secrets.baseline
git commit -m "chore: initialize detect-secrets baseline"
```

---

### Task 3.3: Configure pre-commit hooks

**Files:**
- Create: `.pre-commit-config.yaml`

- [ ] **Step 1: Write `.pre-commit-config.yaml`**

Create `/home/mdoub/Github/railsgoat-security/.pre-commit-config.yaml` with:

```yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ["--baseline", ".secrets.baseline"]
        exclude: "^(docs/scan-reports/|vendor/|node_modules/)"

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-added-large-files
        args: ["--maxkb=500"]
      - id: check-merge-conflict

  - repo: https://github.com/hadolint/hadolint
    rev: v2.13.1-beta
    hooks:
      - id: hadolint
        files: Dockerfile
        args: ["--config", ".hadolint.yaml"]

  - repo: local
    hooks:
      - id: bundler-audit
        name: bundler-audit
        entry: bundle-audit check --update
        language: system
        files: Gemfile\.lock
        pass_filenames: false
```

- [ ] **Step 2: Write `.hadolint.yaml`**

Create `/home/mdoub/Github/railsgoat-security/.hadolint.yaml` with:

```yaml
failure-threshold: error
trusted-registries:
  - docker.io
  - ghcr.io
ignored: []
```

- [ ] **Step 3: Install hooks**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
pre-commit install
pre-commit run --all-files 2>&1 | tee /tmp/precommit-initial.log
```

Expected: hooks installed at `.git/hooks/pre-commit`. Initial run may flag trailing whitespace / missing EOL in old RailsGoat files — re-run `git add -u && git commit --amend --no-edit` to capture the autofixes, then re-run pre-commit until all pass.

- [ ] **Step 4: Commit pre-commit config**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .pre-commit-config.yaml .hadolint.yaml
git commit -m "chore: add pre-commit hooks (detect-secrets, hadolint, bundler-audit, file hygiene)"
```

---

### Task 3.4: Write local scan scripts

**Files:**
- Create: `scripts/scan-secrets.sh`, `scripts/scan-sast.sh`, `scripts/scan-sca.sh`, `scripts/scan-image.sh`, `scripts/scan-dast.sh`, `scripts/generate-sbom.sh`, `scripts/scan-all.sh`

- [ ] **Step 1: `scripts/scan-secrets.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
echo "== Secrets: detect-secrets =="
detect-secrets-hook --baseline .secrets.baseline $(git ls-files) \
  > docs/scan-reports/detect-secrets.txt 2>&1 || {
    echo "New secrets detected. See docs/scan-reports/detect-secrets.txt"
    exit 1
  }
echo "Secrets scan OK"
```

- [ ] **Step 2: `scripts/scan-sast.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
FAIL=0

echo "== SAST: Brakeman =="
bundle exec brakeman \
  --format html --output docs/scan-reports/brakeman.html \
  --format json --output docs/scan-reports/brakeman.json \
  -w2 --no-exit-on-warn || FAIL=1

HIGH=$(jq '[.warnings[] | select(.confidence == "High")] | length' docs/scan-reports/brakeman.json)
if [ "$HIGH" -gt 0 ]; then
  echo "Brakeman: $HIGH High-confidence finding(s) — see docs/scan-reports/brakeman.html"
  FAIL=1
fi

echo "== SAST: Semgrep =="
semgrep scan --config=p/ruby --config=p/security-audit \
  --sarif --output docs/scan-reports/semgrep.sarif \
  --severity=ERROR --error --quiet || FAIL=1

[ "$FAIL" -eq 0 ] && echo "SAST OK" || { echo "SAST FAIL"; exit 1; }
```

- [ ] **Step 3: `scripts/scan-sca.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
FAIL=0

echo "== SCA: bundler-audit =="
bundle-audit check --update \
  | tee docs/scan-reports/bundler-audit.txt
if grep -q "Criticality: Critical" docs/scan-reports/bundler-audit.txt; then
  echo "bundler-audit: Critical CVE present"
  FAIL=1
fi

echo "== SCA: Trivy (filesystem) =="
trivy fs --severity CRITICAL \
  --format json --output docs/scan-reports/trivy-fs.json . || FAIL=1
trivy fs --severity CRITICAL --exit-code 1 --quiet . || FAIL=1

[ "$FAIL" -eq 0 ] && echo "SCA OK" || { echo "SCA FAIL"; exit 1; }
```

- [ ] **Step 4: `scripts/scan-image.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
FAIL=0
IMAGE="${IMAGE:-railsgoat-security:local}"

echo "== Image build =="
docker build -t "$IMAGE" . 1>/dev/null

echo "== Image: Hadolint =="
hadolint --config .hadolint.yaml Dockerfile \
  > docs/scan-reports/hadolint.txt 2>&1 || FAIL=1

echo "== Image: Trivy config =="
trivy config --severity CRITICAL --format json \
  --output docs/scan-reports/trivy-config.json . || FAIL=1

echo "== Image: Trivy image scan =="
trivy image --severity CRITICAL --vuln-type os \
  --format json --output docs/scan-reports/trivy-image-os.json "$IMAGE" || FAIL=1
trivy image --severity HIGH,CRITICAL --vuln-type library \
  --format json --output docs/scan-reports/trivy-image-lib.json "$IMAGE" || FAIL=1

trivy image --severity CRITICAL --vuln-type os --exit-code 1 --quiet "$IMAGE" || FAIL=1
trivy image --severity HIGH,CRITICAL --vuln-type library --exit-code 1 --quiet "$IMAGE" || FAIL=1

[ "$FAIL" -eq 0 ] && echo "Image scan OK" || { echo "Image scan FAIL"; exit 1; }
```

- [ ] **Step 5: `scripts/scan-dast.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
IMAGE="${IMAGE:-railsgoat-security:local}"

echo "== DAST: ZAP baseline =="
SECRET_KEY_BASE=$(openssl rand -hex 64)
docker run --rm -d --name rg-dast -p 3000:3000 \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e RAILS_ENV=production \
  "$IMAGE"

cleanup() { docker stop rg-dast >/dev/null 2>&1 || true; }
trap cleanup EXIT

for i in {1..30}; do
  curl -fsS http://localhost:3000/ >/dev/null 2>&1 && break
  sleep 2
done

docker run --rm --network=host \
  -v "$(pwd)/docs/scan-reports:/zap/wrk" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t http://localhost:3000 \
    -r zap-baseline.html -J zap-baseline.json \
    -I  # return 0 even on warnings, we gate on FAIL-level below

HIGH=$(jq '[.site[].alerts[] | select(.riskcode == "3")] | length' docs/scan-reports/zap-baseline.json)
if [ "$HIGH" -gt 0 ]; then
  echo "ZAP: $HIGH High alert(s)"
  exit 1
fi
echo "DAST OK"
```

- [ ] **Step 6: `scripts/generate-sbom.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/scan-reports
IMAGE="${IMAGE:-railsgoat-security:local}"

echo "== SBOM: Syft (CycloneDX) =="
syft "$IMAGE" -o cyclonedx-json=docs/scan-reports/sbom.cdx.json
syft "$IMAGE" -o spdx-json=docs/scan-reports/sbom.spdx.json

echo "== SBOM CVE scan: Grype =="
grype sbom:docs/scan-reports/sbom.cdx.json \
  --fail-on critical \
  -o json > docs/scan-reports/grype.json || {
    echo "Grype: Critical CVE present"
    exit 1
  }

echo "SBOM OK"
```

- [ ] **Step 7: `scripts/scan-all.sh`**

Create with:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/6] Secrets scan"
./scripts/scan-secrets.sh

echo "[2/6] SAST"
./scripts/scan-sast.sh

echo "[3/6] SCA"
./scripts/scan-sca.sh

echo "[4/6] Image build + scan"
./scripts/scan-image.sh

echo "[5/6] DAST"
./scripts/scan-dast.sh

echo "[6/6] SBOM"
./scripts/generate-sbom.sh

echo ""
echo "All scans complete. Reports in docs/scan-reports/"
```

- [ ] **Step 8: Make all scripts executable**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
chmod +x scripts/*.sh
```

- [ ] **Step 9: Commit scripts**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add scripts/ .hadolint.yaml
git commit -m "feat: add local scan scripts mirroring the CI pipeline"
```

---

### Task 3.5: Run baseline scans and triage findings

- [ ] **Step 1: Run full scan and expect failures**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
./scripts/scan-all.sh 2>&1 | tee /tmp/baseline-scan.log
```

Expected: **failures** — RailsGoat is intentionally vulnerable. Note exit point (which layer first failed). This is the *baseline*.

- [ ] **Step 2: Save baseline reports (rename)**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security/docs/scan-reports
for f in brakeman.html brakeman.json semgrep.sarif bundler-audit.txt trivy-fs.json trivy-image-os.json trivy-image-lib.json trivy-config.json hadolint.txt zap-baseline.html zap-baseline.json sbom.cdx.json sbom.spdx.json grype.json detect-secrets.txt; do
  [ -f "$f" ] && cp "$f" "${f%.*}-baseline.${f##*.}"
done
ls *baseline*
```

Expected: `-baseline.*` copies of each report.

- [ ] **Step 3: Create triage file**

Create `/home/mdoub/Github/railsgoat-security/docs/scan-reports/TRIAGE.md` with:

```markdown
# Baseline triage — 2026-04-23

Initial findings classification. Populated after first `./scripts/scan-all.sh` run.

## Summary

| Layer | Total | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| Brakeman | ? | ? | ? | ? | ? |
| Semgrep | ? | ? | ? | ? | ? |
| bundler-audit | ? | ? | ? | ? | ? |
| Trivy fs | ? | ? | ? | ? | ? |
| Trivy image OS | ? | ? | ? | ? | ? |
| Trivy image libs | ? | ? | ? | ? | ? |
| ZAP | ? | ? | ? | ? | ? |
| Grype | ? | ? | ? | ? | ? |

## To fix (Critical + High)

(Populate from each report. One finding per line: tool, rule/CVE, file:line, planned fix.)

## To document (Medium + Low)

(Populate. One finding per line: tool, rule/CVE, justification for acceptance.)
```

- [ ] **Step 4: Populate TRIAGE.md with actual findings**

Read each baseline report:
- Brakeman: open `docs/scan-reports/brakeman-baseline.html` in browser, count warnings by confidence (High/Medium/Weak)
- Semgrep: `jq '[.runs[0].results[] | .level] | group_by(.) | map({(.[0]): length}) | add' docs/scan-reports/semgrep-baseline.sarif`
- bundler-audit: `grep -c 'Criticality:' docs/scan-reports/bundler-audit-baseline.txt`
- Trivy: `jq '.Results[].Vulnerabilities | group_by(.Severity) | map({(.[0].Severity): length}) | add' docs/scan-reports/trivy-image-lib-baseline.json`
- ZAP: `jq '[.site[].alerts[] | .riskdesc] | group_by(.) | map({(.[0]): length}) | add' docs/scan-reports/zap-baseline-baseline.json`
- Grype: `jq '[.matches[] | .vulnerability.severity] | group_by(.) | map({(.[0]): length}) | add' docs/scan-reports/grype-baseline.json`

Fill the summary table with actual numbers. Then list each Critical/High finding in "To fix" and each Medium/Low in "To document".

- [ ] **Step 5: Commit baseline and triage**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/scan-reports/
git commit -m "chore: baseline scan reports + initial triage"
```

- [ ] **Step 6: Log phase 3 in DEV_JOURNAL**

Append to `docs/DEV_JOURNAL.md`:

```markdown

---

## 2026-04-23 — Phase 3: Security tooling local

**Context:** Install all security tools locally, produce baseline scan
reports, triage findings into "fix" vs "accept" categories.

**Baseline summary:** (see docs/scan-reports/TRIAGE.md for numbers)

**Categorization strategy:**
- Critical + High (any tool) → fix in phase 4
- Medium + Low → document in SECURITY_EXCEPTIONS.md with justification

**Tool surprises:**
(filled in during actual work — what found more/less than expected,
false positives, tool idiosyncrasies)

**Time spent:** X hours
```

Then commit:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/DEV_JOURNAL.md
git commit -m "docs: log phase 3 baseline scan summary"
```

- [ ] **Step 7: Push dev**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push origin dev
```

**✅ Phase 3 checkpoint:**
- All 10 tools run locally
- Baseline reports committed in `docs/scan-reports/*-baseline.*`
- `TRIAGE.md` lists every Critical/High with planned fix and every Medium/Low with planned justification
- DEV_JOURNAL has the phase 3 entry

---

# Phase 4 — Targeted remediation (target: ~4-6h)

**Outcome:** Zero unaccepted Critical/High findings across all tools. `SECURITY_EXCEPTIONS.md` documents every Medium/Low with CVE/CWE, justification, owner, review date. Post-remediation reports committed as `*-final.*`.

**Branch:** all work on `dev`. Each fix = atomic commit.

---

### Task 4.1: Initialize `SECURITY_EXCEPTIONS.md`

**Files:**
- Create: `SECURITY_EXCEPTIONS.md`

- [ ] **Step 1: Write template**

Create `/home/mdoub/Github/railsgoat-security/SECURITY_EXCEPTIONS.md` with:

```markdown
# Security exceptions register

Every finding in this file is a residual risk the project owner has
**formally accepted** rather than fixed. Each entry is reviewable and dated.

Severity policy: entries here are **Medium or Low only**. Critical and High
findings must be fixed, never accepted.

---

## Schema

Every entry MUST include:

- **ID** — unique, e.g. `RG-SEC-001`
- **Tool** — Brakeman / Semgrep / bundler-audit / Trivy / ZAP / Grype
- **Finding** — rule name or CVE
- **Severity** — Medium or Low
- **Location** — file:line or dependency:version
- **Justification** — why accepting this risk is reasonable
- **Mitigation** — compensating control, if any
- **Owner** — person responsible for revisiting (Michel-Ange Doubogan)
- **Accepted date** — ISO date
- **Review date** — ISO date, typically +6 months
- **Ticket** — optional tracker link

---

## Entries

<!-- Populate from TRIAGE.md "To document" section -->
```

- [ ] **Step 2: Commit template**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add SECURITY_EXCEPTIONS.md
git commit -m "docs: add SECURITY_EXCEPTIONS register template"
```

---

### Task 4.2: Generate ignore files matching accepted findings

**Files:**
- Modify: `.brakeman.ignore`, `.semgrepignore`, `.trivyignore`

- [ ] **Step 1: Generate `.brakeman.ignore` interactively**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
bundle exec brakeman -I
```

When prompted, for each Medium/Low finding you chose to accept, enter `i` (ignore) and provide a short note referencing the `RG-SEC-XXX` ID from `SECURITY_EXCEPTIONS.md`. For Critical/High findings, enter `s` (skip — will be fixed, not ignored).

Expected: `.brakeman.ignore` file created with JSON entries.

- [ ] **Step 2: Write `.semgrepignore`**

Create `/home/mdoub/Github/railsgoat-security/.semgrepignore` with:

```
# Semgrep path exclusions (directories not scanned)
vendor/
node_modules/
docs/scan-reports/
tmp/
log/
coverage/
db/migrate/
```

Note: Semgrep rule-level exceptions are done via `# nosemgrep: <rule-id>` comments inline, not via this file. Each inline exception must reference a `RG-SEC-XXX` ID in a comment on the same line.

- [ ] **Step 3: Write `.trivyignore`**

Create `/home/mdoub/Github/railsgoat-security/.trivyignore` with:

```
# Trivy CVE exceptions. Format: one CVE per line, optional comment.
# Each line must correspond to an RG-SEC-XXX entry in SECURITY_EXCEPTIONS.md.
# Format for expiry: "CVE-YYYY-NNNNN exp:YYYY-MM-DD"
#
# Populated during phase 4 remediation.
```

Entries are added later as each Medium/Low dependency finding is accepted.

- [ ] **Step 4: Commit ignore scaffolding**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .brakeman.ignore .semgrepignore .trivyignore
git commit -m "chore: initialize ignore files aligned with SECURITY_EXCEPTIONS"
```

---

### Task 4.3: Remediate Critical/High findings iteratively

This is a loop, not a single task. Repeat the following cycle for each Critical/High finding from `TRIAGE.md`:

- [ ] **Per-finding loop:**

For each finding:

1. **Pick the next unfixed Critical/High from `TRIAGE.md`.**

2. **Apply the fix** to the relevant file. Prefer surgical edits. Examples of common remediations in RailsGoat:
   - **SQLi via string interpolation** → replace `where("name = '#{params[:q]}'")` with `where(name: params[:q])` or sanitized placeholder
   - **Mass assignment** → replace `User.new(params[:user])` with `User.new(user_params)` and define `user_params` with `permit(...)`
   - **IDOR** → replace `Post.find(params[:id])` with `current_user.posts.find(params[:id])`
   - **XSS via `.html_safe`** → remove `.html_safe`, use `sanitize` with allowlist, or escape
   - **Weak crypto** → replace `Digest::MD5` with `bcrypt` for passwords, or `OpenSSL::Digest::SHA256` for integrity
   - **Unsafe deserialization** → replace `Marshal.load` with JSON, replace `YAML.load` with `YAML.safe_load`
   - **Vulnerable gem version** → bump the offending gem in Gemfile, `bundle update <gem>`

3. **Re-run the single-layer scan** to verify:
   ```bash
   # pick one of:
   ./scripts/scan-sast.sh    # for Brakeman/Semgrep fixes
   ./scripts/scan-sca.sh     # for bundler-audit/Trivy fs fixes
   ./scripts/scan-image.sh   # for image-level fixes
   ```

4. **If fix succeeds:** commit atomically:
   ```bash
   git add <exact-files-changed>
   git commit -m "fix: <short description> (Brakeman <rule>, <file>:<line>)"
   ```
   Commit message must reference the tool and rule ID for traceability.

5. **Check off the finding in `TRIAGE.md`** and move to next.

- [ ] **End of loop check:**

After processing all Critical/High items, run the full scan:
```bash
cd /home/mdoub/Github/railsgoat-security
./scripts/scan-all.sh 2>&1 | tee /tmp/post-remediation-scan.log
```

Expected: all gates pass. If any Critical/High remains, it is either:
- A true false positive → document in `SECURITY_EXCEPTIONS.md` with explicit "false-positive" justification and add to the appropriate ignore file
- A finding you cannot fix → escalate by downgrading in `.trivyignore` with explicit expiry date AND a tracker issue link (create a GitHub issue for it)

Either path must produce a written justification. Never silently ignore.

---

### Task 4.4: Populate `SECURITY_EXCEPTIONS.md` for accepted Medium/Low

- [ ] **Step 1: For every Medium/Low entry in `TRIAGE.md`, add a row**

Edit `SECURITY_EXCEPTIONS.md`, appending under `## Entries`:

```markdown
### RG-SEC-001

- **Tool:** Brakeman
- **Finding:** (rule name, e.g. "Dangerous Eval" CWE-95)
- **Severity:** Medium
- **Location:** app/controllers/foo_controller.rb:42
- **Justification:** (concrete reason, e.g. "input originates from admin-only
  form protected by authentication and CSRF, not user-reachable")
- **Mitigation:** (compensating control, e.g. "admin middleware enforces role
  check before reaching controller")
- **Owner:** Michel-Ange Doubogan
- **Accepted date:** 2026-04-23
- **Review date:** 2026-10-23
- **Ticket:** none
```

Repeat for every Medium and Low finding from baseline scans.

- [ ] **Step 2: Commit exceptions**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add SECURITY_EXCEPTIONS.md .brakeman.ignore .semgrepignore .trivyignore
git commit -m "docs: document accepted medium/low risks in SECURITY_EXCEPTIONS"
```

---

### Task 4.5: Generate final scan reports

- [ ] **Step 1: Run full scan and expect green**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
./scripts/scan-all.sh 2>&1 | tee /tmp/final-scan.log
```

Expected: exit 0. If any layer still fails, return to Task 4.3 for that finding.

- [ ] **Step 2: Archive final reports**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security/docs/scan-reports
for f in brakeman.html brakeman.json semgrep.sarif bundler-audit.txt trivy-fs.json trivy-image-os.json trivy-image-lib.json trivy-config.json hadolint.txt zap-baseline.html zap-baseline.json sbom.cdx.json sbom.spdx.json grype.json; do
  [ -f "$f" ] && cp "$f" "${f%.*}-final.${f##*.}"
done
ls *final*
```

Expected: `-final.*` copies alongside `-baseline.*`.

- [ ] **Step 3: Write `docs/scan-reports/README.md` (reader key)**

Create with:

```markdown
# Scan reports

Every security scan produces a report here. Each file exists in two flavors:

- `*-baseline.*` — state at the end of phase 3, before any remediation
- `*-final.*` — state at the end of phase 4, after remediation

Compare them to see the remediation impact.

## Files

| File | What |
|---|---|
| `brakeman-*.html` | SAST findings, browsable by category |
| `brakeman-*.json` | Same findings in machine-readable form |
| `semgrep-*.sarif` | SAST findings in SARIF format (GitHub Security tab) |
| `bundler-audit-*.txt` | Ruby dependency CVEs |
| `trivy-fs-*.json` | Filesystem + dependency CVEs (all ecosystems) |
| `trivy-image-os-*.json` | OS package CVEs in the Docker image |
| `trivy-image-lib-*.json` | Application library CVEs in the Docker image |
| `trivy-config-*.json` | Dockerfile misconfiguration findings |
| `hadolint-*.txt` | Dockerfile lint findings |
| `zap-baseline-*.{html,json}` | Dynamic (runtime) web scan |
| `sbom.cdx.json` | SBOM in CycloneDX format |
| `sbom.spdx.json` | SBOM in SPDX format |
| `grype-*.json` | CVEs scanned from the SBOM |

See [TRIAGE.md](TRIAGE.md) for classification and fixing decisions, and
[../../SECURITY_EXCEPTIONS.md](../../SECURITY_EXCEPTIONS.md) for accepted risks.
```

- [ ] **Step 4: Commit final reports and reader key**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/scan-reports/
git commit -m "chore: post-remediation final scan reports"
```

- [ ] **Step 5: Log phase 4 in DEV_JOURNAL**

Append to `docs/DEV_JOURNAL.md`:

```markdown

---

## 2026-04-23 — Phase 4: Targeted remediation

**Context:** Bring the project from baseline (many Critical/High findings)
to zero unaccepted Critical/High. Medium/Low documented in
SECURITY_EXCEPTIONS.md.

**Remediation pattern:** per-finding atomic commit with tool + rule ID
in the commit message for auditability.

**Categories of fixes applied:** (e.g. SQLi → parametrized queries,
mass assignment → strong_parameters, weak crypto → bcrypt, vulnerable
gems → version bump)

**Categories of risks accepted:** (e.g. admin-only eval with compensating
auth control, false-positive on JS test fixture)

**Surprises:** (what took longer than expected, what was simpler)

**Remediation stats:**
- Critical fixed: X / X
- High fixed: X / X
- Medium accepted: X / X
- Low accepted: X / X

**Time spent:** X hours
```

Commit:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/DEV_JOURNAL.md
git commit -m "docs: log phase 4 remediation stats"
```

---

### Task 4.6: Invoke `simplify` on remediation commits

- [ ] **Step 1: Run simplify on phase 4 diff**

Invoke `/simplify` over the range of commits from end of phase 3 to now. Review suggestions, accept conservative ones, ignore ones that would reintroduce vulnerability patterns.

- [ ] **Step 2: Push dev**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push origin dev
```

**✅ Phase 4 checkpoint:**
- `./scripts/scan-all.sh` exits 0
- `SECURITY_EXCEPTIONS.md` has one entry per accepted Medium/Low finding, all with complete schema
- `docs/scan-reports/*-final.*` exist alongside baselines
- `TRIAGE.md` shows every Critical/High ticked off
- DEV_JOURNAL phase 4 entry populated with stats

---

# Phase 5 — CI pipeline (target: ~3-4h)

**Outcome:** `security.yml` runs on every PR to main, all 8 jobs green. `auto-pr.yml` creates/updates PR dev→main on each push to dev. SARIF uploads appear in GitHub Security tab. GHCR image signed with Cosign.

**Branch:** all work on `dev`.

---

### Task 5.1: Write `auto-pr.yml`

**Files:**
- Create: `.github/workflows/auto-pr.yml`

- [ ] **Step 1: Write workflow**

Create `/home/mdoub/Github/railsgoat-security/.github/workflows/auto-pr.yml` with:

```yaml
name: Auto PR dev → main

on:
  push:
    branches: [dev]

permissions:
  contents: read
  pull-requests: write

jobs:
  open-or-update-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Create or update PR
        uses: peter-evans/create-pull-request@v6
        with:
          base: main
          branch: dev
          title: "Merge dev → main (${{ github.sha }})"
          body: |
            Auto-generated PR from `dev` to `main`.

            Commits included in this PR:

            ${{ github.event.head_commit.message }}

            Security pipeline (`security.yml`) runs automatically on this PR.
            Merge only when all status checks are green.
          draft: false
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .github/workflows/auto-pr.yml
git commit -m "ci: add auto-PR workflow dev → main"
```

---

### Task 5.2: Write `security.yml` — top + secrets + sast jobs

**Files:**
- Create: `.github/workflows/security.yml`

- [ ] **Step 1: Write workflow header and secrets-scan + sast jobs**

Create `/home/mdoub/Github/railsgoat-security/.github/workflows/security.yml` with:

```yaml
name: Security pipeline

on:
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write
  security-events: write
  pull-requests: write

concurrency:
  group: security-${{ github.ref }}
  cancel-in-progress: true

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  secrets-scan:
    name: Secrets (detect-secrets)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install detect-secrets==1.5.0
      - name: Audit baseline
        run: |
          detect-secrets audit --report --baseline .secrets.baseline \
            > detect-secrets-audit.json 2>&1 || true
      - name: Scan vs baseline (fail on new findings)
        run: |
          detect-secrets-hook --baseline .secrets.baseline $(git ls-files)
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: secrets-report
          path: detect-secrets-audit.json
          retention-days: 30

  sast:
    name: SAST (Brakeman + Semgrep)
    runs-on: ubuntu-latest
    needs: secrets-scan
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: Brakeman
        run: |
          bundle exec brakeman \
            --format sarif --output brakeman.sarif \
            --format json --output brakeman.json \
            -w2 --no-exit-on-warn
          HIGH=$(jq '[.warnings[] | select(.confidence == "High")] | length' brakeman.json)
          echo "## Brakeman" >> $GITHUB_STEP_SUMMARY
          echo "High-confidence findings: $HIGH" >> $GITHUB_STEP_SUMMARY
          [ "$HIGH" -eq 0 ] || exit 1

      - name: Upload Brakeman SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: brakeman.sarif
          category: brakeman

      - name: Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: p/ruby p/security-audit
          generateSarif: "1"
        continue-on-error: false

      - name: Upload Semgrep SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: semgrep.sarif
          category: semgrep

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: sast-reports
          path: |
            brakeman.sarif
            brakeman.json
            semgrep.sarif
          retention-days: 30
```

- [ ] **Step 2: Commit progress**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .github/workflows/security.yml
git commit -m "ci: security.yml — secrets + sast jobs"
```

---

### Task 5.3: Extend `security.yml` — sca + docker-build jobs

- [ ] **Step 1: Append to `security.yml`**

Append these jobs (before end of file) in `.github/workflows/security.yml`:

```yaml

  sca:
    name: SCA (bundler-audit + Trivy fs)
    runs-on: ubuntu-latest
    needs: secrets-scan
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: bundler-audit
        run: |
          gem install bundler-audit
          bundle-audit check --update | tee bundler-audit.txt
          if grep -q "Criticality: Critical" bundler-audit.txt; then
            echo "::error::bundler-audit found Critical CVE"
            exit 1
          fi

      - name: Trivy fs
        uses: aquasecurity/trivy-action@0.24.0
        with:
          scan-type: fs
          severity: CRITICAL
          exit-code: "1"
          format: sarif
          output: trivy-fs.sarif

      - name: Upload Trivy fs SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-fs.sarif
          category: trivy-fs

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: sca-reports
          path: |
            bundler-audit.txt
            trivy-fs.sarif
          retention-days: 30

  docker-build:
    name: Docker build + lint
    runs-on: ubuntu-latest
    needs: secrets-scan
    outputs:
      image-digest: ${{ steps.build.outputs.digest }}
    steps:
      - uses: actions/checkout@v4

      - uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          config: .hadolint.yaml
          failure-threshold: error

      - name: Trivy config
        uses: aquasecurity/trivy-action@0.24.0
        with:
          scan-type: config
          severity: CRITICAL
          exit-code: "1"
          format: sarif
          output: trivy-config.sarif

      - name: Upload Trivy config SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-config.sarif
          category: trivy-config

      - uses: docker/setup-buildx-action@v3

      - name: Build image
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          load: true
          push: false
          tags: railsgoat-security:ci
          outputs: type=docker,dest=/tmp/image.tar

      - uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: /tmp/image.tar
          retention-days: 1
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .github/workflows/security.yml
git commit -m "ci: security.yml — sca + docker-build jobs"
```

---

### Task 5.4: Extend `security.yml` — image-scan + dast jobs

- [ ] **Step 1: Append to `security.yml`**

```yaml

  image-scan:
    name: Image scan (Trivy)
    runs-on: ubuntu-latest
    needs: docker-build
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: docker-image
          path: /tmp
      - run: docker load -i /tmp/image.tar

      - name: Trivy image OS (CRITICAL)
        uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: railsgoat-security:ci
          severity: CRITICAL
          vuln-type: os
          exit-code: "1"
          format: sarif
          output: trivy-image-os.sarif

      - name: Trivy image libraries (HIGH+)
        uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: railsgoat-security:ci
          severity: HIGH,CRITICAL
          vuln-type: library
          exit-code: "1"
          format: sarif
          output: trivy-image-lib.sarif

      - name: Upload SARIF (image OS)
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-image-os.sarif
          category: trivy-image-os

      - name: Upload SARIF (image libs)
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-image-lib.sarif
          category: trivy-image-lib

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: image-scan-reports
          path: |
            trivy-image-os.sarif
            trivy-image-lib.sarif
          retention-days: 30

  dast:
    name: DAST (ZAP baseline)
    runs-on: ubuntu-latest
    needs: docker-build
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: docker-image
          path: /tmp
      - run: docker load -i /tmp/image.tar

      - name: Run app
        run: |
          SECRET_KEY_BASE=$(openssl rand -hex 64)
          docker run --rm -d --name rg -p 3000:3000 \
            -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
            -e RAILS_ENV=production \
            railsgoat-security:ci
          for i in {1..30}; do
            curl -fsS http://localhost:3000/ >/dev/null 2>&1 && break
            sleep 2
          done

      - name: ZAP baseline
        uses: zaproxy/action-baseline@v0.13.0
        with:
          target: http://localhost:3000
          fail_action: true
          allow_issue_writing: false
          cmd_options: "-a"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: dast-reports
          path: |
            report_html.html
            report_json.json
          retention-days: 30

      - name: Stop app
        if: always()
        run: docker stop rg || true
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .github/workflows/security.yml
git commit -m "ci: security.yml — image-scan + dast jobs"
```

---

### Task 5.5: Extend `security.yml` — sbom + sign-and-push jobs

- [ ] **Step 1: Append to `security.yml`**

```yaml

  sbom:
    name: SBOM (Syft + Grype)
    runs-on: ubuntu-latest
    needs: [sast, sca, image-scan, dast]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: docker-image
          path: /tmp
      - run: docker load -i /tmp/image.tar

      - name: Syft (CycloneDX)
        uses: anchore/sbom-action@v0
        with:
          image: railsgoat-security:ci
          format: cyclonedx-json
          output-file: sbom.cdx.json
          upload-artifact: false

      - name: Syft (SPDX)
        uses: anchore/sbom-action@v0
        with:
          image: railsgoat-security:ci
          format: spdx-json
          output-file: sbom.spdx.json
          upload-artifact: false

      - name: Grype (Critical only)
        uses: anchore/scan-action@v4
        with:
          sbom: sbom.cdx.json
          fail-build: true
          severity-cutoff: critical
          output-format: sarif
          output-file: grype.sarif

      - name: Upload Grype SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: grype.sarif
          category: grype

      - uses: actions/upload-artifact@v4
        with:
          name: sbom-reports
          path: |
            sbom.cdx.json
            sbom.spdx.json
            grype.sarif
          retention-days: 90

  sign-and-push:
    name: Sign + push (GHCR)
    runs-on: ubuntu-latest
    needs: sbom
    if: github.event_name == 'pull_request' && github.base_ref == 'main'
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: sigstore/cosign-installer@v3

      - name: Compute lowercase image name (GHCR requirement)
        run: echo "IMAGE=$(echo ${{ env.REGISTRY }}/${{ github.repository }} | tr '[:upper:]' '[:lower:]')" >> $GITHUB_ENV

      - name: Login GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build + push
        id: build-push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE }}:pr-${{ github.event.number }}
            ${{ env.IMAGE }}:sha-${{ github.sha }}
            ${{ env.IMAGE }}:latest

      - name: Cosign sign (keyless)
        env:
          DIGEST: ${{ steps.build-push.outputs.digest }}
        run: |
          cosign sign --yes "${IMAGE}@${DIGEST}"

      - name: Write summary
        run: |
          echo "## Image published and signed" >> $GITHUB_STEP_SUMMARY
          echo "- Ref: \`${IMAGE}:sha-${{ github.sha }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- Digest: \`${{ steps.build-push.outputs.digest }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- Verify: \`cosign verify ${IMAGE}:latest --certificate-identity-regexp='https://github.com/Setounkpe7/.*' --certificate-oidc-issuer=https://token.actions.githubusercontent.com\`" >> $GITHUB_STEP_SUMMARY
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add .github/workflows/security.yml
git commit -m "ci: security.yml — sbom + sign-and-push jobs (Cosign keyless)"
```

---

### Task 5.6: Push dev, let auto-PR open, monitor the security pipeline

- [ ] **Step 1: Push**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push origin dev
```

Expected: `auto-pr.yml` triggers on the push. After ~30s, a PR `dev → main` should exist.

- [ ] **Step 2: Verify PR exists**

Run:
```bash
gh pr list --repo Setounkpe7/railsgoat-security
```

Expected: one PR from `dev` to `main`.

- [ ] **Step 3: Watch the security run**

Run:
```bash
gh run watch --repo Setounkpe7/railsgoat-security --exit-status
```

Expected: eventually exit 0 (all jobs green). If red:

1. Identify the failing job:
   ```bash
   gh run view --repo Setounkpe7/railsgoat-security --log-failed
   ```
2. Reproduce locally with the matching `./scripts/scan-*.sh`
3. Fix on `dev`
4. Commit, push, wait for new run

**Loop until green.** This is the monitoring phase described in the user request.

- [ ] **Step 4: Verify GHCR image is pullable and signed**

Run:
```bash
docker pull ghcr.io/setounkpe7/railsgoat-security:sha-$(git rev-parse dev)
cosign verify ghcr.io/setounkpe7/railsgoat-security:sha-$(git rev-parse dev) \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

Expected: image pulls, cosign verification prints a JSON payload (trust established).

---

### Task 5.7: Re-apply branch protection with required status checks

- [ ] **Step 1: Extend `scripts/setup-branch-protection.sh`**

Replace the body of the script (created in Task 1.7) with:

```bash
#!/usr/bin/env bash
set -euo pipefail

OWNER="Setounkpe7"
REPO="railsgoat-security"

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${REPO}/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Secrets (detect-secrets)",
      "SAST (Brakeman + Semgrep)",
      "SCA (bundler-audit + Trivy fs)",
      "Docker build + lint",
      "Image scan (Trivy)",
      "DAST (ZAP baseline)",
      "SBOM (Syft + Grype)",
      "Sign + push (GHCR)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF

echo "Branch protection (with required checks) applied on main."
```

- [ ] **Step 2: Run it**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
./scripts/setup-branch-protection.sh
```

Expected: success message. If it errors saying checks are not recognized, it's because the jobs have not been referenced yet — run it after the first green `security.yml` run, so that GitHub knows the check names.

- [ ] **Step 3: Commit script update**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add scripts/setup-branch-protection.sh
git commit -m "chore: require all security jobs as branch protection checks"
git push origin dev
```

- [ ] **Step 4: Merge the PR to main**

Run:
```bash
gh run watch --repo Setounkpe7/railsgoat-security --exit-status
PR_NUM=$(gh pr list --repo Setounkpe7/railsgoat-security --base main --head dev --json number -q '.[0].number')
gh pr review $PR_NUM --approve --repo Setounkpe7/railsgoat-security 2>/dev/null || echo "Self-approve not allowed, proceeding to merge"
gh pr merge $PR_NUM --squash --delete-branch=false --repo Setounkpe7/railsgoat-security
```

Expected: PR merged. Note: for a solo repo with 0 approvals required, self-merge works. `--delete-branch=false` keeps `dev` alive.

- [ ] **Step 5: Log phase 5 in DEV_JOURNAL**

Append to `docs/DEV_JOURNAL.md`:

```markdown

---

## 2026-04-23 — Phase 5: CI pipeline

**Context:** Implement security.yml (8 jobs) and auto-pr.yml. Iterate
until green. Apply branch protection status checks.

**Job graph:** secrets → [sast, sca, docker-build] → [image-scan, dast] → sbom → sign-and-push

**Total runtime:** X minutes

**Iterations to green:** X (count the runs that failed before success)

**Surprises:** (what broke first, what broke last, what was harder
than expected — e.g. specific SARIF category conflicts, artifact
sizes, runner RAM)

**Cosign verify:** works from local machine with the documented command

**Time spent:** X hours
```

- [ ] **Step 6: Commit journal + push**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git checkout dev
git pull origin dev --ff-only
git add docs/DEV_JOURNAL.md
git commit -m "docs: log phase 5 CI pipeline outcomes"
git push origin dev
```

**✅ Phase 5 checkpoint:**
- `gh run list --repo Setounkpe7/railsgoat-security --branch main --limit 1` shows green
- Image pullable and Cosign-verifiable
- Branch protection active with 8 required status checks
- `main` has received at least one PR-merged commit
- Auto-PR worked end-to-end

---

# Phase 6 — Portfolio (target: ~2h)

**Outcome:** `REPORT.md` (10 sections) and `README.md` written, humanized before first commit. Cross-links set up with `find-one-devsecops-case-study`. `Setounkpe7/Setounkpe7` profile README updated. `add-portfolio` skill invoked, output committed.

**Branch:** work on `dev`.

---

### Task 6.1: Draft `REPORT.md` (10 sections)

**Files:**
- Create: `REPORT.md`

- [ ] **Step 1: Write full draft**

Create `/home/mdoub/Github/railsgoat-security/REPORT.md` with all 10 sections as defined in the spec § 8. Use accessible language, practitioner tone, with acronyms glossed at first occurrence.

Reference material:
- `docs/DEV_JOURNAL.md` — source for challenges, decisions, time actually spent
- `docs/scan-reports/TRIAGE.md` — source for baseline numbers
- `docs/scan-reports/*-baseline.*` vs `*-final.*` — source for measurable results (use `jq` to extract counts)
- `SECURITY_EXCEPTIONS.md` — source for residual risk narrative

The 10 sections, as templates:

```markdown
# railsgoat-security — DevSecOps hardening case study

## 1. Context and objective
(Why RailsGoat, what role I played, what "done" means for this project.)

## 2. Initial diagnostic
(State of the legacy at takeover: Ruby 2.x EOL, Rails 4-5 EOL, X intentional
vulnerabilities across OWASP Top 10, no CI, no hooks, no SBOM. Concrete
numbers from baseline scans.)

## 3. Key decisions and justifications
### 3.1 Minimum-viable Ruby migration
(Why booting on Ruby 3.3 / Rails 7.1 instead of a full rewrite.)
### 3.2 Remediation scope B
(Why fix-critical/high + document-medium/low beats fix-everything.)
### 3.3 Per-tool gating policy
(Why each tool has its own threshold.)

## 4. Challenges encountered
(Real obstacles from DEV_JOURNAL, in chronological order.)

## 5. DevSecOps pipeline built
(Secrets → SAST → SCA → Docker build+lint → Image scan → DAST → SBOM →
Sign+push. One paragraph per layer. Include the job graph picture.)

## 6. Measurable results
| Metric | Baseline | Final |
|---|---|---|
| Critical findings | X | 0 |
| High findings | X | 0 |
| Medium findings | X | X (documented) |
| CVE in Gemfile.lock | X | Y |
| SBOM packages covered | — | N |
| Pipeline runtime | — | X minutes |

## 7. Limitations and residual risks
(Medium findings deliberately left in place — list with justification
summaries. No live deployment. No peer review. DAST baseline scope.
No production traffic.)

## 8. Senior engineering practices applied
(Atomic commits, upstream attribution, accepted-risk register with
owner+date, branch protection, image signature, auditable baselines,
local-first validation.)

## 9. What I would do differently / with more time
(Honest anti-over-selling.)

## 10. How to read this repo
(Navigation guide for the hurried reviewer: 5 files to open, 3 commands
to run. This project was built with AI assistance to speed implementation.)
```

Section 10 contains the one-sentence AI mention (per user memory).

- [ ] **Step 2: Humanize the draft BEFORE first commit**

Per user memory: `humanizer` must run before the first commit of a public-facing doc.

Invoke the humanizer skill on `REPORT.md`:
```
/humanizer
```

Scope: `REPORT.md`. Accept the humanized version, save it over the draft.

- [ ] **Step 3: First commit of REPORT.md (already humanized)**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add REPORT.md
git commit -m "docs: add portfolio case study REPORT"
```

---

### Task 6.2: Write `README.md`

**Files:**
- Create: `README.md` (overwrite the RailsGoat one inherited from snapshot)

- [ ] **Step 1: Write `README.md`**

Create `/home/mdoub/Github/railsgoat-security/README.md` with:

```markdown
# railsgoat-security

DevSecOps hardening of [OWASP RailsGoat](https://github.com/OWASP/railsgoat) —
a deliberately vulnerable Ruby on Rails training application — with a full
security pipeline (secrets, SAST, SCA, DAST, SBOM, signed container image)
and documented risk acceptance for residual findings.

## At a glance

- 🛡️ 8-layer GitHub Actions security pipeline on every PR to `main`
- 📦 Signed Docker image on GHCR (Cosign keyless, Sigstore)
- 📜 CycloneDX SBOM as a first-class deliverable
- 🧭 Branch-protected `main`, auto-PR from `dev`
- 🔍 Findings visible in the GitHub Security tab via SARIF uploads

## Repo navigation

| File | Purpose |
|---|---|
| [REPORT.md](REPORT.md) | Full case study — read this first |
| [SECURITY_EXCEPTIONS.md](SECURITY_EXCEPTIONS.md) | Formally accepted residual risks |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Pipeline diagram + branch/PR flow |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | How to reproduce every scan locally |
| [docs/DEV_JOURNAL.md](docs/DEV_JOURNAL.md) | Dated technical decisions log |
| [docs/scan-reports/](docs/scan-reports/) | Baseline + final scan outputs |
| [.github/workflows/security.yml](.github/workflows/security.yml) | CI pipeline source of truth |

## Pull the signed image

```bash
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Related work

- [find-one-devsecops-case-study](https://github.com/Setounkpe7/find-one-devsecops-case-study) — my first DevSecOps case study

## Credits

Built on OWASP RailsGoat (MIT), see [CREDITS.md](CREDITS.md) and [NOTICE.md](NOTICE.md).
This project was built with AI assistance to speed implementation; engineering
decisions (scope, tooling, gating, risk acceptance) are my own.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Humanize README before commit**

Invoke `/humanizer` on `README.md`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add README.md
git commit -m "docs: add project README with repo navigation"
```

---

### Task 6.3: Write `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`

**Files:**
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/RUNBOOK.md`

- [ ] **Step 1: Write `docs/ARCHITECTURE.md`**

Create with:

```markdown
# Architecture

## Branch and PR flow

```
main ← (protected, squash-merge only, 8 required status checks)
 ↑
 │  Auto-PR via peter-evans/create-pull-request
 │
dev ← direct pushes, pre-commit hooks enforced locally
```

## CI pipeline (`security.yml`)

```
secrets-scan
    │
    ├── sast ────────────┐
    ├── sca ─────────────┤
    └── docker-build ────┼──→ image-scan ──┐
                         │                 │
                         └──→ dast ────────┤
                                           ↓
                                         sbom
                                           ↓
                                  sign-and-push (Cosign + GHCR)
```

## Gating policy (per-tool thresholds)

| Tool | Fail threshold |
|---|---|
| detect-secrets | Any new finding |
| Brakeman | High+ |
| Semgrep | ERROR |
| bundler-audit | Critical |
| Trivy fs | Critical |
| Trivy image (OS) | Critical |
| Trivy image (libs) | High+ |
| Hadolint | Error |
| Trivy config | Critical |
| ZAP baseline | High alert |
| Grype (on SBOM) | Critical |

## Artifact lifecycle

- Scan reports → committed to `docs/scan-reports/` as baseline + final
- Pipeline artifacts → GitHub Actions artifacts (30-day retention for most, 90 days for SBOM)
- SARIF → uploaded to GitHub Security tab
- Signed image → pushed to `ghcr.io/setounkpe7/railsgoat-security`
```

- [ ] **Step 2: Write `docs/RUNBOOK.md`**

Create with:

```markdown
# Runbook — reproducing every scan locally

## Prerequisites

- Docker
- Ruby 3.3 (via rbenv/asdf matching `.ruby-version`)
- Python 3.12 + pipx
- `gh` CLI authenticated

## One-time setup

```bash
pipx install detect-secrets pre-commit semgrep
gem install brakeman bundler-audit
# Trivy, Hadolint, Syft, Grype, Cosign: see scripts/install-tools.sh (TODO)
pre-commit install
bundle install
```

## Run the full pipeline locally

```bash
./scripts/scan-all.sh
```

Reports land in `docs/scan-reports/`. The script exits non-zero on any
gate failure (same semantics as CI).

## Run one layer at a time

```bash
./scripts/scan-secrets.sh
./scripts/scan-sast.sh
./scripts/scan-sca.sh
./scripts/scan-image.sh
./scripts/scan-dast.sh
./scripts/generate-sbom.sh
```

## Verify the published signed image

```bash
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## Re-apply branch protection

```bash
./scripts/setup-branch-protection.sh
```

## Troubleshooting

- `docker run` returns 500 on `/` → ensure `SECRET_KEY_BASE` env var is set
- `detect-secrets` flags a legitimate baseline entry → `detect-secrets audit .secrets.baseline`
- `brakeman -I` crashes → delete `.brakeman.ignore` and re-run
- Trivy DB update fails → `trivy --cache-dir ~/.cache/trivy image --download-db-only`
```

- [ ] **Step 3: Commit**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/ARCHITECTURE.md docs/RUNBOOK.md
git commit -m "docs: add ARCHITECTURE and RUNBOOK"
```

---

### Task 6.4: Cross-link with `find-one-devsecops-case-study`

**Files:**
- Modify: `/home/mdoub/Github/find-one-devsecops-case-study/REPORT.md` (if it exists)

- [ ] **Step 1: Locate the existing REPORT in find-one**

Run:
```bash
ls /home/mdoub/Github/find-one-devsecops-case-study/*.md
```

Expected: a `REPORT.md` or similar case-study doc.

- [ ] **Step 2: Add a "Related work" section**

At the end of `find-one-devsecops-case-study/REPORT.md`, append:

```markdown

---

## Related work

- [railsgoat-security](https://github.com/Setounkpe7/railsgoat-security) —
  DevSecOps hardening of OWASP RailsGoat: 8-layer CI pipeline, targeted
  remediation of critical/high findings, formally documented residual risks,
  signed container image on GHCR.
```

- [ ] **Step 3: Commit in that repo**

If `find-one-devsecops-case-study` is its own git repo:
```bash
cd /home/mdoub/Github/find-one-devsecops-case-study
git add REPORT.md
git commit -m "docs: add cross-link to railsgoat-security"
git push
```

---

### Task 6.5: Update `Setounkpe7/Setounkpe7` profile README

- [ ] **Step 1: Clone profile repo if not local**

Run:
```bash
cd /home/mdoub/Github/Setounkpe7
[ -d .git ] || gh repo clone Setounkpe7/Setounkpe7 .
```

- [ ] **Step 2: Add DevSecOps section to profile README**

Edit the profile `README.md`. Add (or update) a section:

```markdown
## DevSecOps projects

- **[railsgoat-security](https://github.com/Setounkpe7/railsgoat-security)** —
  Hardened OWASP RailsGoat with an 8-layer GitHub Actions security pipeline:
  secrets scanning, SAST (Brakeman + Semgrep), SCA (bundler-audit + Trivy),
  DAST (ZAP baseline), SBOM (CycloneDX), Hadolint, Cosign-signed image on GHCR.
  Residual risks are formally accepted in a dated register.

- **[find-one-devsecops-case-study](https://github.com/Setounkpe7/find-one-devsecops-case-study)** —
  My first DevSecOps case study.

These projects were built with AI assistance to speed implementation;
engineering decisions are my own.
```

- [ ] **Step 3: Humanize before commit**

Invoke `/humanizer` on the modified profile README.

- [ ] **Step 4: Commit and push**

Run:
```bash
cd /home/mdoub/Github/Setounkpe7
git add README.md
git commit -m "docs: add DevSecOps projects section"
git push
```

---

### Task 6.6: Invoke `add-portfolio` skill

- [ ] **Step 1: Run add-portfolio on railsgoat-security**

From the repo directory, invoke:
```
/add-portfolio
```

The skill operates on the current repo and produces a polished portfolio artifact. Accept outputs, commit.

- [ ] **Step 2: Push final dev**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git push origin dev
```

- [ ] **Step 3: Wait for CI green, then merge final PR**

Run:
```bash
gh run watch --repo Setounkpe7/railsgoat-security --exit-status
PR_NUM=$(gh pr list --repo Setounkpe7/railsgoat-security --base main --head dev --json number -q '.[0].number')
gh pr merge $PR_NUM --squash --delete-branch=false --repo Setounkpe7/railsgoat-security
```

---

### Task 6.7: Final DEV_JOURNAL entry

- [ ] **Step 1: Append phase 6 summary to `docs/DEV_JOURNAL.md`**

```markdown

---

## 2026-04-23 — Phase 6: Portfolio

**Context:** Produce recruiter-facing REPORT.md, README.md,
ARCHITECTURE.md, RUNBOOK.md. Cross-link with find-one-devsecops-case-study.
Update Setounkpe7 profile README. Invoke add-portfolio skill.

**Humanizer applied before first commit:** REPORT.md, README.md,
profile README.

**Total project time (all 6 phases):** X hours
```

- [ ] **Step 2: Commit and push**

Run:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/DEV_JOURNAL.md
git commit -m "docs: log phase 6 portfolio delivery"
git push origin dev
```

---

### Task 6.8: Verify definition of done

- [ ] **Step 1: Walk the 13 criteria from spec § 10**

For each criterion, run the verification command and confirm:

```bash
# 1. Main has PR-merged commits only
git log main --oneline --first-parent | head -5
gh api /repos/Setounkpe7/railsgoat-security/branches/main/protection | jq '.allow_force_pushes.enabled'

# 2. Latest security.yml on main green
gh run list --repo Setounkpe7/railsgoat-security --branch main --limit 1 --json conclusion

# 3. Image pullable and cosign verify passes
docker pull ghcr.io/setounkpe7/railsgoat-security:latest
cosign verify ghcr.io/setounkpe7/railsgoat-security:latest \
  --certificate-identity-regexp='https://github.com/Setounkpe7/.*' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# 4. SBOM present
ls docs/scan-reports/sbom.cdx.json

# 5. SECURITY_EXCEPTIONS populated
head -40 SECURITY_EXCEPTIONS.md

# 6. Zero unaccepted HIGH/CRITICAL
./scripts/scan-all.sh && echo "All gates green"

# 7. Branch protection active
gh api /repos/Setounkpe7/railsgoat-security/branches/main/protection | jq '.required_status_checks.contexts'

# 8. pre-commit install works on a fresh clone
TMP=$(mktemp -d); cd $TMP && gh repo clone Setounkpe7/railsgoat-security . && pre-commit install && cd - && rm -rf $TMP

# 9. scan-all.sh runs on fresh machine (partial proof: it passed locally)
./scripts/scan-all.sh

# 10. docker run returns 200
docker run --rm -d --name rg-final -p 3000:3000 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e RAILS_ENV=production \
  ghcr.io/setounkpe7/railsgoat-security:latest
sleep 15
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/
docker stop rg-final

# 11. REPORT.md has 10 sections and was humanized pre-commit
grep -E '^## ' REPORT.md | wc -l
git log --follow REPORT.md --oneline  # first commit should be the humanized version

# 12. Cross-links in place
grep -l railsgoat-security /home/mdoub/Github/find-one-devsecops-case-study/*.md
grep -l railsgoat-security /home/mdoub/Github/Setounkpe7/README.md

# 13. add-portfolio has run
git log --oneline --grep="portfolio" | head -3
```

- [ ] **Step 2: Tick off all 13 in a final commit on dev**

Add a file `docs/DEFINITION_OF_DONE.md` listing the 13 criteria with ✅ next to each + the command output proving it. Commit and push.

Final push + merge:
```bash
cd /home/mdoub/Github/railsgoat-security
git add docs/DEFINITION_OF_DONE.md
git commit -m "docs: record definition-of-done verification outputs"
git push origin dev

gh run watch --repo Setounkpe7/railsgoat-security --exit-status
PR_NUM=$(gh pr list --repo Setounkpe7/railsgoat-security --base main --head dev --json number -q '.[0].number')
gh pr merge $PR_NUM --squash --repo Setounkpe7/railsgoat-security
```

**✅ Phase 6 checkpoint = project done:**
- All 13 DoD criteria verified
- Final merge to main complete
- Portfolio live and navigable

---

## Appendix A — Commit message conventions used

- `chore:` — scaffolding, config, non-feature work
- `feat:` — new capability (workflows, scripts, containerization)
- `fix:` — vulnerability remediation, always includes tool + rule in body
- `docs:` — markdown changes
- `ci:` — workflow file changes

## Appendix B — When things go wrong

- **Pipeline job fails unexpectedly:** reproduce locally with matching `scripts/scan-*.sh`, fix, push, rewatch.
- **Rails 7.1 migration blocks:** fall back to Rails 6.1, log decision in DEV_JOURNAL, proceed.
- **Trivy DB outdated in CI:** `trivy-action` handles its own DB; pin the action version if flakiness persists.
- **Cosign verify fails locally but works in CI:** you need `cosign` v2+ locally — check with `cosign version`.
- **Self-approve blocked:** the 0-approvals branch protection should allow self-merge; if not, toggle `required_approving_review_count` to 0 explicitly.
- **`peter-evans/create-pull-request` does not trigger security.yml:** this is a known GitHub limitation — `GITHUB_TOKEN` from the default action cannot trigger subsequent workflows. Fix: create a fine-grained PAT with `pull-requests: write` and use it in `auto-pr.yml` (`token: ${{ secrets.PAT }}`).
