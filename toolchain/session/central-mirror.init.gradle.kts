// Sends Maven Central traffic to Google's mirror of it. Cloud sessions share
// outbound IPs, which Maven Central rate-limits (HTTP 429).
//
// Each mavenCentral() is searched through the mirror instead, and Maven Central
// itself is kept as the last repository, so an artifact the mirror doesn't have
// yet, such as a release from the last few hours, still resolves. Only those
// misses reach Maven Central.
//
// Installed into ~/.gradle/init.d/ on cloud sessions by apply.sh, and into the
// toolchain image's Gradle home.
val centralMirror = "https://maven-central.storage-download.googleapis.com/maven2/"
val mavenCentralUrl = "https://repo.maven.apache.org/maven2/"
val mirrorName = "MavenCentralMirror"
val fallbackName = "MavenCentralFallback"

fun ArtifactRepository.urlString() = (this as? MavenArtifactRepository)?.url?.toString().orEmpty()
fun ArtifactRepository.isMirror() = urlString() == centralMirror

// Points mavenCentral() at the mirror, including repositories declared after this runs.
fun RepositoryHandler.useCentralMirror() = all {
    if (this is MavenArtifactRepository && name != fallbackName &&
        urlString().trimEnd('/') == mavenCentralUrl.trimEnd('/')
    ) {
        setUrl(centralMirror)
    }
}

// Orders the search: the Gradle Plugin Portal next to last, because it answers a
// miss by redirecting to Maven Central, and a 429 there stops the search before
// later repositories (such as a snapshot repository) are tried; Maven Central
// last, for whatever the mirror doesn't have yet. A build that declares no plugin
// repositories gets the portal it would have used by default.
fun RepositoryHandler.orderRepositories(isPluginRepositories: Boolean) {
    if (isPluginRepositories && isEmpty()) gradlePluginPortal()
    val portals = filter { it.urlString().startsWith("https://plugins.gradle.org") }
    portals.forEach { remove(it) }
    if (portals.isNotEmpty() && none { it.isMirror() }) {
        maven(centralMirror) { name = mirrorName }
    }
    portals.forEach { add(it) }
    if (any { it.isMirror() } && none { it.name == fallbackName }) {
        maven(mavenCentralUrl) { name = fallbackName }
    }
}

beforeSettings {
    pluginManagement.repositories.useCentralMirror()
    dependencyResolutionManagement.repositories.useCentralMirror()
}

settingsEvaluated {
    pluginManagement.repositories.orderRepositories(isPluginRepositories = true)
    dependencyResolutionManagement.repositories.orderRepositories(isPluginRepositories = false)
}

allprojects {
    buildscript.repositories.useCentralMirror()
    repositories.useCentralMirror()
    afterEvaluate {
        repositories.orderRepositories(isPluginRepositories = false)
    }
}
