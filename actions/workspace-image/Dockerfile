# A workspace image: kmp-toolchain plus the Gradle, Kotlin/Native and Kotlin npm
# caches from building a set of repos, for cloud sessions. Built by action.yml.
#
# The build context holds the repos side by side, the same layout as a cloud
# session, plus workspace.repos (what to build in each) and warm.sh.

ARG TOOLCHAIN=ghcr.io/embarrasdf/kmp-toolchain:latest
# The previous version of this image, or the toolchain itself on the first build.
ARG PREVIOUS=${TOOLCHAIN}

FROM ${PREVIOUS} AS previous

# Warm up on the current toolchain, starting from the previous caches, so only
# new dependencies download and only changed modules compile.
FROM ${TOOLCHAIN} AS warm
COPY --from=previous /opt/gradle-home /opt/gradle-home
COPY --from=previous /opt/konan /opt/konan
COPY --from=previous /root/.kotlin/kotlin-npm-tooling /root/.kotlin/kotlin-npm-tooling
COPY . /src/
RUN bash /src/warm.sh /src/workspace.repos

# Cache layers, ordered by how often they change: a typical push changes only
# the build cache, so that's all a refresh has to download.
FROM ${TOOLCHAIN}
COPY --from=warm /opt/konan /opt/konan
COPY --from=warm /root/.kotlin/kotlin-npm-tooling /root/.kotlin/kotlin-npm-tooling
COPY --from=warm /out/deps/ /opt/gradle-home/
COPY --from=warm /out/build/ /opt/gradle-home/caches/
