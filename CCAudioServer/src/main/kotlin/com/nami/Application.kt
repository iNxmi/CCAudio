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
import java.awt.Color
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.nio.file.Path
import java.nio.file.Paths
import java.security.MessageDigest
import javax.imageio.ImageIO
import kotlin.io.path.*

fun main(args: Array<String>): Unit = io.ktor.server.netty.EngineMain.main(args)

fun Application.module() {
    val musicPath = Paths.get(environment.config.property("ccaudioserver.path").getString())
    updateMusic(musicPath)

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

fun getKeyHash(path: Path, chunkSizeInBytes: Int): String {
    val digest = MessageDigest.getInstance("SHA-256")

    val a = digest.digest(path.readBytes())
    val b = digest.digest(chunkSizeInBytes.toString().toByteArray(Charsets.UTF_8))
    val bytes = digest.digest(a + b)

    return bytes.joinToString("") { "%02x".format(it) }
}

val cache = mutableMapOf<String, Stream>()
val music = sortedSetOf<Music>(compareBy (String.CASE_INSENSITIVE_ORDER) { it.path.toString() })

val COLORS = mapOf(
    "0" to Color(0xF0, 0xF0, 0xF0),
    "1" to Color(0xF2, 0xB2, 0x33),
    "2" to Color(0xE5, 0x7F, 0xD8),
    "3" to Color(0x99, 0xB2, 0xF2),
    "4" to Color(0xDE, 0xDE, 0x6C),
    "5" to Color(0x7F, 0xCC, 0x19),
    "6" to Color(0xF2, 0xB2, 0xCC),
    "7" to Color(0x4C, 0x4C, 0x4C),
    "8" to Color(0x99, 0x99, 0x99),
    "9" to Color(0x4C, 0x99, 0xB2),
    "a" to Color(0xB2, 0x66, 0xE5),
    "b" to Color(0x33, 0x66, 0xCC),
    "c" to Color(0x7F, 0x66, 0x4C),
    "d" to Color(0x57, 0xA6, 0x4E),
    "e" to Color(0xCC, 0x4C, 0x4C),
    "f" to Color(0x11, 0x11, 0x11)
)

fun createCover(musicPath: Path): String? {
    println(musicPath)

    val output = createTempFile(prefix = "cc_audio_server", suffix = ".png")

    val command = listOf(
        "ffmpeg",
        "-y",
        "-i", musicPath.absolutePathString(),
        "-an",
        "-vcodec", "copy",
        output.absolutePathString()
    )

    val process = ProcessBuilder(command).start()

    val exitCode = process.waitFor()
    if (exitCode != 0) {
        deleteFile(output)
        println(process.errorStream.bufferedReader().readText())
        return null
    }

    val originalImage = ImageIO.read(output.toFile())
    deleteFile(output)

    val resizedImage = BufferedImage( 96,64,BufferedImage.TYPE_INT_RGB)
    val graphics = resizedImage.createGraphics()
    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
    graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
    graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
    graphics.drawImage(originalImage, 0, 0,  96,64, null)
    graphics.dispose()

    val result = StringBuilder()
    for(y in 0 until 64) {
        for (x in 0 until 96) {
            val originalColor = Color(resizedImage.getRGB(x, y))
            var mappedColorCode = ""
            var lastDistance = Int.MAX_VALUE
            for ((cKey, cValue) in COLORS) {
                val rComponent = originalColor.red - cValue.red
                val gComponent = originalColor.green - cValue.green
                val bComponent = originalColor.blue - cValue.blue

                val distance = rComponent * rComponent + gComponent * gComponent + bComponent * bComponent
                if (distance >= lastDistance)
                    continue

                lastDistance = distance
                mappedColorCode = cKey
            }
            result.append(mappedColorCode)
        }
        result.appendLine()
    }

    return result.toString()
}

fun updateMusic(musicPath: Path) {
    musicPath.createDirectories()

    val result = musicPath.walk()
        .filter { it.isRegularFile() }
        .map {
            val music = Music(it, it.toString().replace(musicPath.toString(), ""), createCover(it))
            println(music)
            music
        }

    music.clear()
    music.addAll(result)
}

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
    "-c:a", "pcm_s8",
    "-ar", "48000",
    "-af", "aresample=resampler=soxr:dither_method=triangular_hp",
    "-f", "s8",
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

fun Route.httpRoutes(musicPath: Path) {
    post("/api/refresh") {
        updateMusic(musicPath)
        call.respond(HttpStatusCode.OK)
    }

    get("/api/list") {
        call.respond(music.map { it.name })
    }

    post("/api/request") {
        //TODO rename to 'index'
        val id = call.request.queryParameters["index"]?.toIntOrNull()
        if (id == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@post
        }

        val selected = music.toList().getOrNull(id)
        if(selected == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@post
        }

        val chunkSizeInBytes = call.request.queryParameters["samples_per_chunk"]?.toIntOrNull()
        if (chunkSizeInBytes == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@post
        }

        val hash = getKeyHash(selected.path, chunkSizeInBytes)
        if (!cache.containsKey(hash)) {
            val bytes = transcode(selected.path)
            if (bytes == null) {
                call.respond(HttpStatusCode.InternalServerError)
                return@post
            }

            val chunks = bytes.chunked(chunkSizeInBytes).map { it.toByteArray() }
            val stream = Stream(chunkSizeInBytes, chunks, bytes.size)
            cache[hash] = stream
        }

        val stream = cache[hash]!!
        val response = mapOf(
            "hash" to hash,
            "music" to selected,
            "chunk_size_in_bytes" to stream.chunkSizeInBytes,
            "number_of_chunks" to stream.chunks.size,
            "number_of_bytes" to stream.totalBytes,
            "number_of_samples" to stream.chunks.sumOf { it.size }
        )

        call.respond(response)
    }

    get("/api/chunk") {
        val hash = call.request.queryParameters["hash"]
        if (hash == null) {
            call.respond(HttpStatusCode.BadRequest)
            return@get
        }

        val chunkIndex = call.request.queryParameters["index"]?.toIntOrNull()
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