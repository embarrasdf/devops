# kmp-toolchain: everything a build needs except the project's own dependencies.
# Versions live in versions.env; change them there, not here.
#
# Cache images build on top of this (actions/cache-image), and cloud sessions
# copy the toolchain out of it (cloud/setup.sh).

ARG BASE=ubuntu:24.04
FROM ${BASE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip \
      libatomic1 \
 && rm -rf /var/lib/apt/lists/*

COPY versions.env install-toolchain.sh /opt/toolchain/
RUN bash /opt/toolchain/install-toolchain.sh

# Files that cloud/setup.sh runs on a session VM.
COPY session/ /opt/toolchain/session/

# Fixed cache locations, so they're found no matter what HOME is (GitHub Actions
# container jobs set HOME=/github/home). Cache images fill these folders.
ENV JAVA_HOME=/opt/jdk \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/opt/gradle-home \
    KONAN_DATA_DIR=/opt/konan
ENV PATH=/opt/jdk/bin:/opt/android-sdk/platform-tools:$PATH
RUN mkdir -p /opt/gradle-home/init.d /opt/konan \
 && cp /opt/toolchain/session/central-mirror.init.gradle.kts /opt/gradle-home/init.d/

LABEL org.opencontainers.image.source=https://github.com/embarrasdf/devops \
      org.opencontainers.image.description="JDK, Android SDK and git-lfs for embarrasdf Kotlin Multiplatform builds"
