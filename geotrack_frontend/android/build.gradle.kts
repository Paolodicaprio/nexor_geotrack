allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // --- DÉBUT DE LA CORRECTION ISAR ---
    // On injecte le namespace manquant spécifiquement pour la librairie Isar
    afterEvaluate {
        if (project.name == "isar_flutter_libs") {
            project.extensions.configure<com.android.build.gradle.LibraryExtension> {
                namespace = "dev.isar.isar_flutter_libs"
            }
        }
    }
    project.evaluationDependsOn(":app")

}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
