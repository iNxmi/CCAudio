package com.example

import io.ktor.serialization.jackson.jackson
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import java.nio.file.Paths

fun main()  {
    embeddedServer(Netty, port = 8080) {

        install(ContentNegotiation) {
            jackson()
        }

        routing {
            httpRoutes()
            webSocketRoutes()
        }

    }.start(wait = true)
}

val PATH_MUSIC = Paths.get("src/main/resources/music")
fun Route.httpRoutes() {
    get("/list") {
        val file = PATH_MUSIC.toFile()
        val set = file.listFiles().toSortedSet()
        call.respond(set)
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