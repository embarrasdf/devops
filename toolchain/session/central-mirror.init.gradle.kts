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

// The Gradle Plugin Portal redirects many downloads to Maven Central. Make sure
// the mirror is searched before the portal, including when a build declares no
// plugin repositories and would otherwise use the portal alone.
fun RepositoryHandler.putMirrorBeforePortal() {
    if (isEmpty()) gradlePluginPortal()
    val portal = indexOfFirst { it.urlString().startsWith("https://plugins.gradle.org") }
    if (portal < 0 || take(portal).any { it.urlString() == centralMirror }) return
    val mirror = maven(centralMirror) { name = "MavenCentralMirror" }
    remove(mirror)
    add(portal, mirror)
}

beforeSettings {
    pluginManagement.repositories.useCentralMirror()
    dependencyResolutionManagement.repositories.useCentralMirror()
}

settingsEvaluated {
    pluginManagement.repositories.putMirrorBeforePortal()
}

allprojects {
    buildscript.repositories.useCentralMirror()
    repositories.useCentralMirror()
}
