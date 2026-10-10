# kmp-toolchain: everything a build needs except the project's own dependencies.
# Versions live in versions.env; change them there, not here.
#
# Cache images build on top of this (actions/cache-image), and cloud sessions
# copy the toolchain out of it (cloud/setup.sh).

# Canonical's official image, from AWS's public registry rather than Docker Hub,
# whose anonymous pull limits are much tighter.
ARG BASE=public.ecr.aws/ubuntu/ubuntu:24.04
FROM ${BASE}

# libatomic1 is for Node (Kotlin/Wasm and JS builds); the rest are the libraries
# chrome-headless-shell links against, plus a font for tests that render text.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip \
      libatomic1 \
      libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 libdbus-1-3 \
      libgbm1 libglib2.0-0t64 libnspr4 libnss3 libx11-6 libxcb1 libxcomposite1 \
      libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 fonts-liberation \
 && rm -rf /var/lib/apt/lists/*

COPY versions.env install-toolchain.sh /opt/toolchain/
RUN bash /opt/toolchain/install-toolchain.sh

# Files that cloud/setup.sh runs on a session VM.
COPY session/ /opt/toolchain/session/

# Fixed cache locations, so they're found no matter what HOME is (GitHub Actions
# container jobs set HOME=/github/home). Cache images fill these folders, plus
# Kotlin's npm tooling under /root/.kotlin, where cloud sessions look for it.
ENV JAVA_HOME=/opt/jdk \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/opt/gradle-home \
    KONAN_DATA_DIR=/opt/konan \
    CHROME_BIN=/opt/chrome/chrome-headless-shell
ENV PATH=/opt/jdk/bin:/opt/android-sdk/platform-tools:$PATH
RUN mkdir -p /opt/gradle-home/init.d /opt/konan /root/.kotlin/kotlin-npm-tooling \
 && cp /opt/toolchain/session/central-mirror.init.gradle.kts /opt/gradle-home/init.d/

LABEL org.opencontainers.image.source=https://github.com/embarrasdf/devops \
      org.opencontainers.image.description="JDK, Android SDK, git-lfs and headless Chrome for embarrasdf Kotlin Multiplatform builds"
