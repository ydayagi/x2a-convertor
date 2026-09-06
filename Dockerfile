# x2a-convertor — hermetic (Konflux) container image.
#
# This image is built with NO network access (Konflux hermetic build). All
# content is pre-fetched by Hermeto/cachi2 from committed lockfiles:
#   - RPMs   : rpms.in.yaml -> rpms.lock.yaml           (prefetch type "rpm")
#   - Ruby   : Gemfile      -> Gemfile.lock             (prefetch type "bundler")
#   - Python : requirements.txt + requirements-build.txt (prefetch type "pip")
#
# Nothing here may call the network (no dnf from remote, no gem install, no
# `uv sync`, no pip index). See .tekton/ for the prefetch wiring.
FROM registry.access.redhat.com/ubi10/ubi:latest

# --- System packages (from the RPM prefetch) ------------------------------
# python3.14 satisfies pyproject `requires-python >=3.13` (UBI10 has no
# python3.13 RPM; the default python3 is 3.12). ruby + bundler build and run
# the Chef/Puppet CLIs; the toolchain compiles native gem/wheel extensions.
# Hermeto injects the prefetched repo, so this dnf runs fully offline.
RUN dnf install -y \
    python3.14 \
    python3.14-pip \
    python3.14-devel \
    ruby \
    ruby-devel \
    rubygem-bundler \
    git \
    gcc \
    gcc-c++ \
    make \
    cmake \
    libffi-devel \
    libyaml-devel \
    && dnf clean all

WORKDIR /app
COPY . /app

# --- Python runtime -------------------------------------------------------
# We do NOT use `uv sync` (it downloads packages and its own interpreter).
# Instead: a venv on the system python3.14, deps installed by pip from the
# prefetched wheels. `uv` is kept only as the offline runtime launcher so the
# `uv run app.py ...` invocation contract (RHDH x2a-job-script.sh and the
# standalone CLI docs) keeps working with zero network — see UV_* below.
ENV UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_NO_SYNC=1 \
    UV_OFFLINE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=/usr/bin/python3.14 \
    PATH="/app/.venv/bin:${PATH}"

RUN python3.14 -m venv /app/.venv

# App dependencies (prefetched wheels). Source the Hermeto env INLINE so its
# PIP_* (offline index / find-links) applies only to this layer.
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; \
    elif [ -f /hermeto/hermeto.env ]; then . /hermeto/hermeto.env; fi \
    && /app/.venv/bin/pip install --no-cache-dir -r requirements.txt

# uv itself (offline launcher only, pinned+hashed in requirements-build.txt).
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; \
    elif [ -f /hermeto/hermeto.env ]; then . /hermeto/hermeto.env; fi \
    && python3.14 -m pip install --no-cache-dir -r requirements-build.txt

# --- Ruby CLIs (chef-cli, berks, r10k) ------------------------------------
# The convertor shells out to `chef-cli`, `berks` and `r10k` via
# shutil.which(...) from arbitrary working directories (temp dirs, module
# roots). Hermeto's bundler prefetch vendors the gems but does NOT put their
# executables on PATH, so we generate binstubs into /usr/local/bin.
# BUNDLE_GEMFILE/BUNDLE_PATH are pinned as absolute env so the binstubs locate
# the Gemfile and vendored gems no matter the caller's cwd.
ENV BUNDLE_GEMFILE=/app/Gemfile \
    BUNDLE_PATH=/app/vendor/bundle
RUN if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; \
    elif [ -f /hermeto/hermeto.env ]; then . /hermeto/hermeto.env; fi \
    && bundle install \
    && bundle binstubs chef-cli berkshelf r10k --path /usr/local/bin

# Accept Chef licenses non-interactively.
ENV CHEF_LICENSE=accept-no-persist

# --- Product (Conforma registry-standard) labels --------------------------
# `cpe` MUST match the ProdSec-assigned CPE and the ReleasePlanAdmission
# releaseNotes.cpe exactly. PLACEHOLDER pending ProdSec assignment.
LABEL cpe="cpe:/a:redhat:x2a_convertor:1" \
      name="x2a-convertor" \
      com.redhat.component="x2a-convertor" \
      version="0.1.0" \
      release="1" \
      summary="X2Ansible convertor: LLM-assisted migration of Chef/Puppet to Ansible" \
      description="Terminal application that converts Chef/Puppet automation to Ansible using an LLM multi-agent pipeline." \
      io.k8s.display-name="X2Ansible Convertor" \
      io.k8s.description="Terminal application that converts Chef/Puppet automation to Ansible using an LLM multi-agent pipeline." \
      io.openshift.tags="x2ansible,ansible,migration" \
      distribution-scope="public" \
      vendor="Red Hat, Inc." \
      url="https://github.com/x2ansible/x2a-convertor"

# Standalone / CLI entrypoint. The RHDH job overrides the command and calls
# `uv run app.py <phase>`, which resolves to the offline /app/.venv via UV_*.
ENTRYPOINT ["uv", "run", "app.py"]
