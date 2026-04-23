# syntax=docker/dockerfile:1.7

# ===== Build stage =====
FROM ruby:3.4.1-slim-bookworm AS build

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test:mysql:openshift" \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      curl \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "$(grep -A1 'BUNDLED WITH' Gemfile.lock | tail -n1 | tr -d ' ')" && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf /usr/local/bundle/cache/*.gem && \
    find /usr/local/bundle -name "*.c" -delete && \
    find /usr/local/bundle -name "*.o" -delete

COPY . .

# ===== Runtime stage =====
FROM ruby:3.4.1-slim-bookworm AS runtime

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test:mysql:openshift" \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libsqlite3-0 \
      libyaml-0-2 \
      curl \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1000 app && \
    useradd app --uid 1000 --gid 1000 --create-home --shell /bin/bash

WORKDIR /app

COPY --from=build --chown=app:app /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=app:app /app /app

# Entrypoint: ensure DB is prepared (idempotent), then exec the CMD
RUN printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -e' \
      'mkdir -p tmp/pids db log' \
      'bundle exec rails db:prepare' \
      'exec "$@"' \
    > /usr/local/bin/docker-entrypoint && \
    chmod +x /usr/local/bin/docker-entrypoint && \
    chown -R app:app /app

USER app:app

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -fsS http://localhost:3000/ || exit 1

ENTRYPOINT ["docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
