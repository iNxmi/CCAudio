package com.example

import io.ktor.http.*
import io.ktor.serialization.jackson.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.httpMethod
import io.ktor.server.request.path
import io.ktor.server.request.uri
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import org.slf4j.event.Level
import java.nio.file.Paths
import java.security.MessageDigest
import kotlin.io.path.absolutePathString
import kotlin.io.path.createTempFile
import kotlin.io.path.readBytes

val PATH_MUSIC = Paths.get("music")

fun main() {
    embeddedServer(Netty, port = 8080) {

        install(CallLogging) {
            level = Level.INFO

            format { call ->
                val status = call.response.status()
                val httpMethod = call.request.httpMethod.value
                val path = call.request.uri
                "[$status] $httpMethod $path"
            }
        }
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

const val CHUNK_SIZE_IN_BYTES = 128 * 1024

data class Stream(
    val chunkSizeInBytes: Int,
    val chunks: List<ByteArray>
)

fun getKeyHash(file:String, chunkSizeInBytes: Int): String {
    val digest = MessageDigest.getInstance("SHA-256")

    val a = digest.digest(file.toByteArray(Charsets.UTF_8))
    val b = digest.digest(chunkSizeInBytes.toString().toByteArray(Charsets.UTF_8))
    val bytes = digest.digest(a + b)

    return bytes.joinToString("") { "%02x".format(it) }
}

val cache = mutableMapOf<String, Stream>()

fun Route.httpRoutes() {
    get("/list") {
        val file = PATH_MUSIC.toFile()
        val set = file.listFiles().map { it.name }.toSortedSet()
        call.respond(set)
    }

    get("/request") {
        val fileName = call.request.queryParameters["file"]
        if (fileName == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val chunkSizeInBytes = call.request.queryParameters["chunkSizeInBytes"]?.toIntOrNull() ?: CHUNK_SIZE_IN_BYTES

        val hash = getKeyHash(fileName, chunkSizeInBytes)

        if (!cache.containsKey(hash)) {


            val outputFile = createTempFile(prefix = "cc_audio_server", suffix = ".pcm")

            val path = PATH_MUSIC.resolve(fileName)

            val command = listOf(
                "ffmpeg",
                "-y",
                "-i", path.absolutePathString(),
                "-map", "0:a:0",
                "-ac", "1",
                "-f", "s8",
                "-c:a", "pcm_s8",
                "-ar", "48000",
                outputFile.absolutePathString()
            )

            val process = ProcessBuilder(command)
                .redirectErrorStream(true)
                .start()

            val exitCode = process.waitFor()
            if (exitCode != 0) {
                call.respond(HttpStatusCode.InternalServerError)
                return@get
            }

            val bytes = outputFile.readBytes().toList()
            val chunks = bytes.chunked(chunkSizeInBytes).map { it.toByteArray() }

            val stream = Stream(chunkSizeInBytes, chunks)
            cache[hash] = stream
        }

        val stream = cache[hash]!!
        val response = mapOf(
            "hash" to hash,
            "chunk_size_in_bytes" to stream.chunkSizeInBytes,
            "number_of_chunks" to stream.chunks.size
        )

        call.respond(response)
    }

    get("/stream") {
        val hash = call.request.queryParameters["hash"]
        if (hash == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val chunkIndex = call.request.queryParameters["chunk"]?.toIntOrNull()
        if (chunkIndex == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        if (!cache.containsKey(hash)) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val stream = cache[hash]!!
        val chunk = stream.chunks[chunkIndex]
        val string = chunk.toString(Charsets.UTF_8)
        call.respond(string)
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