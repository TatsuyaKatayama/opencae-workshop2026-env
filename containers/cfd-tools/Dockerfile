# syntax=docker/dockerfile:1.7
ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
FROM ${UBUNTU_IMAGE} AS certificates
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates=20240203

FROM ${UBUNTU_IMAGE} AS base
COPY --from=certificates /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ARG APT_SNAPSHOT=20261024T000000Z
ENV DEBIAN_FRONTEND=noninteractive
# 全 CPU で同日時点の署名付きパッケージ一覧を使用する。
RUN rm -f /etc/apt/sources.list.d/ubuntu.sources && \
    printf 'deb [check-valid-until=no] http://snapshot.ubuntu.com/ubuntu/%s noble main universe\ndeb [check-valid-until=no] http://snapshot.ubuntu.com/ubuntu/%s noble-updates main universe\ndeb [check-valid-until=no] http://snapshot.ubuntu.com/ubuntu/%s noble-security main universe\n' \
        "$APT_SNAPSHOT" "$APT_SNAPSHOT" "$APT_SNAPSHOT" > /etc/apt/sources.list && \
    printf 'Acquire::Retries "3";\n' > /etc/apt/apt.conf.d/80-retries

FROM base AS compiler
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl xz-utils flex bison cmake ninja-build \
    zlib1g-dev libosmesa6-dev libfreetype-dev \
    python3-dev python3-venv && rm -rf /var/lib/apt/lists/*

FROM compiler AS paraview-arm64
ARG PARAVIEW_URL
ARG PARAVIEW_SHA256
ARG BUILD_JOBS=2
RUN curl -fSL --retry 3 "$PARAVIEW_URL" -o /tmp/paraview.tar.xz && \
    echo "$PARAVIEW_SHA256  /tmp/paraview.tar.xz" | sha256sum -c - && \
    mkdir /src && tar -xJf /tmp/paraview.tar.xz -C /src --strip-components=1 && \
    rm /tmp/paraview.tar.xz
RUN --mount=type=cache,id=paraview-5.13.3-arm64,target=/build,sharing=locked \
    cmake -S /src -B /build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/paraview \
    -DPARAVIEW_BUILD_EDITION=CATALYST_RENDERING \
    -DPARAVIEW_USE_QT=OFF -DPARAVIEW_USE_PYTHON=ON -DPARAVIEW_USE_MPI=OFF \
    -DPARAVIEW_BUILD_TESTING=OFF -DPARAVIEW_ENABLE_EXAMPLES=OFF \
    -DVTK_USE_X=OFF -DVTK_OPENGL_HAS_OSMESA=ON -DVTK_OPENGL_HAS_EGL=OFF \
    -DPython3_EXECUTABLE=/usr/bin/python3 && \
    cmake --build /build --parallel "$BUILD_JOBS" && \
    cmake --install /build && \
    mkdir -p /opt/paraview/share/licenses && \
    cd /src && find . -type f \( -iname 'license*' -o -iname 'copying*' -o -iname 'copyright*' \) \
        -exec cp --parents -t /opt/paraview/share/licenses '{}' +

FROM base AS paraview-amd64
ARG PARAVIEW_AMD64_URL
ARG PARAVIEW_AMD64_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -fsSL --retry 3 "$PARAVIEW_AMD64_URL" -o /tmp/paraview.tar.gz && \
    echo "$PARAVIEW_AMD64_SHA256  /tmp/paraview.tar.gz" | sha256sum -c - && \
    mkdir -p /opt/paraview && tar -xzf /tmp/paraview.tar.gz -C /opt/paraview --strip-components=1 && \
    rm /tmp/paraview.tar.gz

FROM paraview-${TARGETARCH} AS paraview

FROM compiler AS uv-download
ARG TARGETARCH
ARG UV_VERSION
ARG UV_ARM64_SHA256
ARG UV_AMD64_SHA256
RUN case "$TARGETARCH" in \
        arm64) arch=aarch64; hash="$UV_ARM64_SHA256" ;; \
        amd64) arch=x86_64; hash="$UV_AMD64_SHA256" ;; \
        *) exit 1 ;; \
    esac && \
    curl -fSL --retry 3 "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-$arch-unknown-linux-gnu.tar.gz" -o /tmp/uv.tgz && \
    echo "$hash  /tmp/uv.tgz" | sha256sum -c - && \
    mkdir /uv && tar -xzf /tmp/uv.tgz -C /uv --strip-components=1 && \
    curl -fsSL --retry 3 "https://raw.githubusercontent.com/astral-sh/uv/$UV_VERSION/LICENSE-MIT" -o /uv/LICENSE-MIT && \
    curl -fsSL --retry 3 "https://raw.githubusercontent.com/astral-sh/uv/$UV_VERSION/LICENSE-APACHE" -o /uv/LICENSE-APACHE

FROM base AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl python3 python3-venv python-is-python3 \
    ffmpeg openmpi-bin libscotch-7.0 libptscotch-7.0 libfftw3-double3 \
    libreadline8t64 libgmp10 libmpfr6 libgomp1 libosmesa6 libgl1-mesa-dri \
    libfreetype6 fontconfig zlib1g && rm -rf /var/lib/apt/lists/*
ARG OPENFOAM_DEB_VERSION
ARG OPENFOAM_KEY_SHA256
RUN mkdir -p /etc/apt/keyrings /opt/workshop-manifest && \
    curl -fsSL --retry 3 https://dl.openfoam.com/pubkey.gpg -o /etc/apt/keyrings/openfoam.asc && \
    echo "$OPENFOAM_KEY_SHA256  /etc/apt/keyrings/openfoam.asc" | sha256sum -c - && \
    echo 'deb [signed-by=/etc/apt/keyrings/openfoam.asc] https://dl.openfoam.com/repos/deb noble main' > /etc/apt/sources.list.d/openfoam.list && \
    apt-get update && apt-get install -y --no-install-recommends "openfoam2606-default=$OPENFOAM_DEB_VERSION" && \
    apt-cache show "openfoam2606-default=$OPENFOAM_DEB_VERSION" > /opt/workshop-manifest/openfoam-package.txt && \
    rm -rf /var/lib/apt/lists/*
COPY --from=uv-download /uv/uv /usr/local/bin/uv
COPY --from=uv-download /uv/LICENSE* /usr/local/share/licenses/uv/
COPY containers/cfd-tools/requirements.lock /opt/workshop-manifest/requirements.lock
RUN uv venv --python /usr/bin/python3 /opt/post-venv && \
    uv pip install --python /opt/post-venv/bin/python --require-hashes \
        -r /opt/workshop-manifest/requirements.lock && uv cache clean
RUN apt-get update && apt-get install -y --no-install-recommends libnss-wrapper && rm -rf /var/lib/apt/lists/*
COPY --from=paraview /opt/paraview /opt/paraview
COPY containers/cfd-tools/scripts/entrypoint.sh /usr/local/bin/cfd-entrypoint
COPY containers/cfd-tools/scripts/pv-command.sh /usr/local/bin/pv-command
COPY examples/smoke /opt/workshop-smoke
COPY versions.env /opt/workshop-manifest/versions.env
# ParaView 配布物の MPI バイナリを PATH に入れず、可視化コマンドだけ公開する。
RUN chmod 755 /usr/local/bin/cfd-entrypoint /usr/local/bin/pv-command && \
    ln -s pv-command /usr/local/bin/pvpython && \
    ln -s pv-command /usr/local/bin/pvbatch && \
    dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > /opt/workshop-manifest/packages.tsv && \
    ffmpeg -buildconf > /opt/workshop-manifest/ffmpeg-buildconf.txt 2>&1 && \
    uv pip freeze --python /opt/post-venv/bin/python > /opt/workshop-manifest/python-packages.txt
ENV PATH="/opt/post-venv/bin:$PATH" \
    HOME=/tmp/opencae-home MPLBACKEND=Agg LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/cfd-entrypoint"]
CMD ["bash"]
