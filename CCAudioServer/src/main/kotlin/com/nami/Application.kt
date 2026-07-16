package com.nami

import io.ktor.http.*
import io.ktor.serialization.jackson.*
import io.ktor.server.application.*
import io.ktor.server.plugins.*
import io.ktor.server.plugins.calllogging.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.slf4j.event.Level
import java.nio.file.Path
import java.nio.file.Paths
import java.security.MessageDigest
import kotlin.io.path.*

fun main(args: Array<String>): Unit = io.ktor.server.netty.EngineMain.main(args)

fun Application.module() {
    val musicPath = Paths.get(environment.config.property("ccaudioserver.path").getString())
    println(musicPath.absolutePathString())
    musicPath.createDirectories()

    install(CallLogging) {
        level = Level.INFO

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
        httpRoutes(musicPath)
    }
}

data class Stream(
    val chunkSizeInBytes: Int,
    val chunks: List<ByteArray>,
    val totalBytes: Int,
)

fun getKeyHash(path: Path, chunkSizeInBytes: Int): String {
    val digest = MessageDigest.getInstance("SHA-256")

    val a = digest.digest(path.readBytes())
    val b = digest.digest(chunkSizeInBytes.toString().toByteArray(Charsets.UTF_8))
    val bytes = digest.digest(a + b)

    return bytes.joinToString("") { "%02x".format(it) }
}

val cache = mutableMapOf<String, Stream>()

fun deleteFile(path: Path): Boolean {
    val success = path.deleteIfExists()

    if (!success)
        System.err.println("Warning: Failed to delete '$path'.")

    return success
}

fun command(input: Path, output: Path) = listOf(
    "ffmpeg",
    "-y",
    "-i", input.absolutePathString(),
    "-map", "0:a:0",
    "-ac", "1",
    "-f", "s8",
    "-c:a", "pcm_s8",
    "-ar", "48000",
    output.absolutePathString()
)

fun transcode(path: Path): List<Byte>? {
    val output = createTempFile(prefix = "cc_audio_server", suffix = ".pcm")

    val command = command(input = path, output = output)

    val process = ProcessBuilder(command)
        .redirectErrorStream(true)
        .start()

    val exitCode = process.waitFor()

    if (exitCode != 0) {
        deleteFile(output)
        return null
    }

    val result = output.readBytes().toList()
    deleteFile(output)

    return result
}

data class Music(
    val path: Path,
    val name: String
)

fun getMusic(path: Path) = path.walk()
    .filter { it.isRegularFile() }
    .map { Music(it, it.toString().replace(path.toString(), "")) }
    .toList()
    .sortedWith (compareBy (String.CASE_INSENSITIVE_ORDER) { it.path.toString() })

fun Route.httpRoutes(musicPath: Path) {
    get("/list") {
        val music = getMusic(musicPath).map { it.name }
        call.respond(music)
    }

    get("/request") {
        //TODO rename to 'index'
        val id = call.request.queryParameters["file"]?.toIntOrNull()
        if (id == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val music = getMusic(musicPath)
        val selected = music[id]

        val chunkSizeInBytes = call.request.queryParameters["chunkSizeInBytes"]?.toIntOrNull()
        if (chunkSizeInBytes == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val hash = getKeyHash(selected.path, chunkSizeInBytes)
        if (!cache.containsKey(hash)) {
            val bytes = transcode(selected.path)
            if (bytes == null) {
                call.respond(HttpStatusCode.InternalServerError)
                return@get
            }

            val chunks = bytes.chunked(chunkSizeInBytes).map { it.toByteArray() }
            val stream = Stream(chunkSizeInBytes, chunks, bytes.size)
            cache[hash] = stream
        }

        val stream = cache[hash]!!
        val response = mapOf(
            "hash" to hash,
            "chunk_size_in_bytes" to stream.chunkSizeInBytes,
            "number_of_chunks" to stream.chunks.size,
            "number_of_bytes" to stream.totalBytes,
            "number_of_samples" to stream.chunks.sumOf { it.size }
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

        val response = mapOf(
            "samples" to chunk.toList(),
            "size" to chunk.size
        )

        call.respond(response)
    }
}