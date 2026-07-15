package com.example

import io.ktor.http.HttpStatusCode
import io.ktor.serialization.jackson.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import java.nio.file.Paths
import kotlin.io.path.absolute

val PATH_MUSIC = Paths.get("music")

fun main() {
    embeddedServer(Netty, port = 8080) {

        install(WebSockets)
        install(ContentNegotiation) {
            jackson()
        }

        routing {
            httpRoutes()
            webSocketRoutes()
        }

    }.start(wait = true)
}

fun Route.httpRoutes() {
    get("/list") {
        val file = PATH_MUSIC.toFile()
        val set = file.listFiles().map { it.name }.toSortedSet()
        call.respond(set)
    }

    get("/transcode") {
        val fileName = call.request.queryParameters["file"]
        if(fileName == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val path = PATH_MUSIC.resolve(fileName)

        val command = listOf(
            "ffmpeg",
            "-y",
            "-i", path.absolute().toString(),
            "-map", "0:a:0",
            "-ac", "1",
            "-f", "s8",
            "-c:a", "pcm_s8",
            "-ar", "48000",
            "OUTPUT.pcm"
        )

        val process = ProcessBuilder(command)
            .redirectErrorStream(true)
            .start()

        val output = process.inputStream.bufferedReader().use { it.readText() }
        val exitCode = process.waitFor()

        call.respond(output)
    }
}

fun Route.webSocketRoutes() {
    webSocket("/echo") {
        for (frame in incoming) {
            if (frame !is Frame.Text)
                continue

            val receivedText = frame.readText()
            println(receivedText)
            send(Frame.Text(receivedText))
        }
    }
}