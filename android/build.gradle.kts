allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Force every Android library sub-module to compile against the same
// SDK the app targets. Some plugins (e.g. flutter_local_notifications' deps)
// declare compileSdk=34 or 35 while their transitive libraries require 36,
// which trips CheckAarMetadata.
//
// This afterEvaluate override MUST live in the same subprojects block as
// the layout.buildDirectory redirection, and it MUST run BEFORE the
// `evaluationDependsOn(":app")` block or Gradle refuses the callback.
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
