FROM judge0/compilers:1.4.0 AS production

ENV JUDGE0_HOMEPAGE "https://judge0.com"
LABEL homepage=$JUDGE0_HOMEPAGE

ENV JUDGE0_SOURCE_CODE "https://github.com/judge0/judge0"
LABEL source_code=$JUDGE0_SOURCE_CODE

ENV JUDGE0_MAINTAINER "Herman Zvonimir Došilović <hermanz.dosilovic@gmail.com>"
LABEL maintainer=$JUDGE0_MAINTAINER

ENV PATH "/usr/local/ruby-2.7.0/bin:/opt/.gem/bin:$PATH"
ENV GEM_HOME "/opt/.gem/"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      cron \
      libpq-dev \
      sudo && \
    rm -rf /var/lib/apt/lists/* && \
    echo "gem: --no-document" > /root/.gemrc && \
    gem install bundler:2.1.4 && \
    npm install -g --unsafe-perm aglio@2.3.0

# ── cgroup v2 fix: rebuild isolate from ioi/isolate v2.4 ─────────────────────
# The base image ships isolate built from judge0/isolate@ad39cc4d (cgroup v1
# era). We replace it with the upstream ioi/isolate v2.4 which has full cgroup
# v2 support via --cg flag. We skip isolate-cg-keeper (systemd unit helper)
# since it isn't used by Judge0's worker — only `isolate` and
# `isolate-check-environment` are needed.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libcap-dev \
      libseccomp-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 --branch v2.4 https://github.com/ioi/isolate.git /tmp/isolate && \
    cd /tmp/isolate && \
    make -j$(nproc) isolate isolate-check-environment && \
    install -m 4755 isolate /usr/local/bin/isolate && \
    install isolate-check-environment /usr/local/bin/isolate-check-environment && \
    rm -rf /tmp/isolate && \
    isolate --version
# ─────────────────────────────────────────────────────────────────────────────

EXPOSE 2358

WORKDIR /api

COPY Gemfile* ./
RUN RAILS_ENV=production bundle

COPY cron /etc/cron.d
RUN cat /etc/cron.d/* | crontab -

COPY . .

ENTRYPOINT ["/api/docker-entrypoint.sh"]
CMD ["/api/scripts/server"]

RUN useradd -u 1000 -m -r judge0 && \
    echo "judge0 ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers && \
    chown judge0: /api/tmp/

USER judge0

ENV JUDGE0_VERSION "1.13.1"
LABEL version=$JUDGE0_VERSION


FROM production AS development

CMD ["sleep", "infinity"]
