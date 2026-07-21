package com.nami

import com.nami.ccaudio.controller.mediaRoutes
import com.nami.ccaudio.repository.MediaRepository
import com.nami.ccaudio.service.MediaService
import io.ktor.serialization.jackson.*
import io.ktor.server.application.*
import io.ktor.server.plugins.*
import io.ktor.server.plugins.calllogging.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.routing.*
import org.slf4j.event.Level
import java.nio.file.Path
import java.nio.file.Paths
import java.security.MessageDigest
import kotlin.io.path.readBytes

fun main(args: Array<String>): Unit = io.ktor.server.netty.EngineMain.main(args)

fun Application.module() {
    val musicPath = Paths.get(environment.config.property("ccaudioserver.path").getString())

    val mediaRepository = MediaRepository()
    val mediaService = MediaService(mediaRepository, musicPath)

    install(CallLogging) {
        level = Level.DEBUG

        format { call ->
            val status = call.response.status()
            val httpMethod = call.request.httpMethod.value
            val path = call.request.uri
            val origin = call.request.origin.remoteAddress
            "$origin [$status] $httpMethod $path"
        }
    }

    install(ContentNegotiation) {
        jackson()
    }

    routing {
        mediaRoutes(mediaService, mediaRepository)
    }
}

fun getKeyHash(path: Path, chunkSizeInBytes: Int): String {
    val digest = MessageDigest.getInstance("SHA-256")

    val a = digest.digest(path.readBytes())
    val b = digest.digest(chunkSizeInBytes.toString().toByteArray(Charsets.UTF_8))
    val bytes = digest.digest(a + b)

    return bytes.joinToString("") { "%02x".format(it) }
}