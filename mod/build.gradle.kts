plugins {
    kotlin("jvm") version "1.9.20"
    id("eclipse")
    id("maven-publish")
    id("net.minecraftforge.gradle") version "5.1.+"
    id("org.parchmentmc.data") version "1.3.1"
}

version = "1.0.0"
group = "cn.qlm.player2"

java.toolchain.languageVersion.set(JavaLanguageVersion.of(17))

minecraft {
    mappings("parchment", "2023.09.03-1.20.1")

    runs {
        val runConfig = Action<net.minecraftforge.gradle.userdev.RunConfig> {
            workingDirectory(file("run"))
            property("forge.logging.markers", "REGISTRIES")
            property("forge.logging.console.level", "debug")
            mods { create("player2") { source(sourceSets.main.get()) } }
        }
        create("client", runConfig)
        create("server", runConfig)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    minecraft("net.minecraftforge:forge:1.20.1-47.4.22")
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("com.neovisionaries:nv-websocket-client:2.14")
    implementation("com.google.code.gson:gson:2.10.1")
}

tasks.withType<ProcessResources> {
    inputs.property("version", project.version)
    filesMatching(listOf("META-INF/mods.toml")) {
        expand("version" to project.version)
    }
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs = listOf("-Xjvm-default=all")
    }
}
