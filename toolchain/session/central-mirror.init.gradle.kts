// Sends Maven Central traffic to Google's mirror of it. Cloud sessions share
// outbound IPs, which Maven Central rate-limits (HTTP 429).
//
// Installed into ~/.gradle/init.d/ on cloud sessions by apply.sh.
// Trade-off: the mirror can trail Maven Central by a few hours after a release.
val centralMirror = "https://maven-central.storage-download.googleapis.com/maven2/"

fun ArtifactRepository.urlString() = (this as? MavenArtifactRepository)?.url?.toString().orEmpty()

// Rewrites mavenCentral(), including repositories declared after this runs.
fun RepositoryHandler.useCentralMirror() = all {
    if (this is MavenArtifactRepository && urlString().trimEnd('/') == "https://repo.maven.apache.org/maven2") {
        setUrl(centralMirror)
    }
}

// The Gradle Plugin Portal answers a miss by redirecting to Maven Central, and a
// 429 there stops the search before later repositories, such as a snapshot
// repository, are tried. So the portal goes last, with the mirror ahead of it,
// including when a build declares no plugin repositories and would otherwise
// use the portal alone.
fun RepositoryHandler.searchPluginPortalLast() {
    if (isEmpty()) gradlePluginPortal()
    val portals = filter { it.urlString().startsWith("https://plugins.gradle.org") }
    if (portals.isEmpty()) return
    portals.forEach { remove(it) }
    if (none { it.urlString() == centralMirror }) {
        maven(centralMirror) { name = "MavenCentralMirror" }
    }
    portals.forEach { add(it) }
}

beforeSettings {
    pluginManagement.repositories.useCentralMirror()
    dependencyResolutionManagement.repositories.useCentralMirror()
}

settingsEvaluated {
    pluginManagement.repositories.searchPluginPortalLast()
    dependencyResolutionManagement.repositories.searchPluginPortalLast()
}

allprojects {
    buildscript.repositories.useCentralMirror()
    repositories.useCentralMirror()
}
