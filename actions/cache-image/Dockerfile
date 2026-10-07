# <repo>-cache: kmp-toolchain plus one repo's Gradle and Kotlin/Native caches.
# Built by action.yml. The build context holds the repo at repo/ and
# gradle-plugins at gradle-plugins/, the same layout as a cloud session.

ARG TOOLCHAIN
# The previous <repo>-cache image, or the toolchain itself on the first build.
ARG PREVIOUS=${TOOLCHAIN}

FROM ${PREVIOUS} AS previous

# Warm up on the current toolchain, starting from the previous caches, so only
# new dependencies download and only changed modules compile.
FROM ${TOOLCHAIN} AS warm
ARG WARM_TASKS
COPY --from=previous /opt/gradle-home /opt/gradle-home
COPY --from=previous /opt/konan /opt/konan
COPY . /src/
RUN bash /src/warm.sh ${WARM_TASKS}

# Two cache layers, ordered by how often they change: a typical push changes
# only the build cache, so that's all a refresh has to download.
FROM ${TOOLCHAIN}
COPY --from=warm /opt/konan /opt/konan
COPY --from=warm /out/deps/ /opt/gradle-home/
COPY --from=warm /out/build/ /opt/gradle-home/caches/
