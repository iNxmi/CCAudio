package com.nami.ccaudio.service

import com.nami.ccaudio.entity.MediaEntity
import com.nami.ccaudio.repository.MediaRepository
import java.awt.Color
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.nio.file.Path
import javax.imageio.ImageIO
import kotlin.io.path.absolutePathString
import kotlin.io.path.createDirectories
import kotlin.io.path.createTempFile
import kotlin.io.path.deleteIfExists
import kotlin.io.path.isRegularFile
import kotlin.io.path.readBytes
import kotlin.io.path.walk

class MediaService(
    private val repository: MediaRepository,
    private val path: Path
) {

    inline fun <T> withTemporaryFile(suffix: String = ".tmp", block: (Path) -> T): T {
        val path = createTempFile("ccaudio_server_", suffix)
        return try {
            block(path)
        } finally {
            if(!path.deleteIfExists())
                System.err.println("Warning: Failed to delete '$path'.")
        }
    }

    private val COLORS = mapOf(
        "0" to Color(0xF0, 0xF0, 0xF0), "1" to Color(0xF2, 0xB2, 0x33),
        "2" to Color(0xE5, 0x7F, 0xD8), "3" to Color(0x99, 0xB2, 0xF2),
        "4" to Color(0xDE, 0xDE, 0x6C), "5" to Color(0x7F, 0xCC, 0x19),
        "6" to Color(0xF2, 0xB2, 0xCC), "7" to Color(0x4C, 0x4C, 0x4C),
        "8" to Color(0x99, 0x99, 0x99), "9" to Color(0x4C, 0x99, 0xB2),
        "a" to Color(0xB2, 0x66, 0xE5), "b" to Color(0x33, 0x66, 0xCC),
        "c" to Color(0x7F, 0x66, 0x4C), "d" to Color(0x57, 0xA6, 0x4E),
        "e" to Color(0xCC, 0x4C, 0x4C), "f" to Color(0x11, 0x11, 0x11)
    )

    init {
        update()
    }

    fun convertToStringImage(image: BufferedImage, width: Int, height: Int): String {
        val resizedImage = BufferedImage( width, height,BufferedImage.TYPE_INT_RGB)
        val graphics = resizedImage.createGraphics()
        graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
        graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        graphics.drawImage(image, 0, 0,  width,height, null)
        graphics.dispose()

        val result = StringBuilder()
        for(y in 0 until height) {
            for (x in 0 until width) {
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

    private fun getCover(input: Path): BufferedImage? = withTemporaryFile(".png") { output ->
        val command = listOf(
            "ffmpeg",
            "-y",
            "-i", input.absolutePathString(),
            "-an",
            "-vcodec", "copy",
            output.absolutePathString()
        )

        val process = ProcessBuilder(command)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()

        val code = process.waitFor()
        if (code != 0)
            return null

        return ImageIO.read(output.toFile())
    }

    private fun getSamples(input: Path): List<Byte>? = withTemporaryFile(".pcm") { output ->
        val command = listOf(
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

        val process = ProcessBuilder(command)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()

        val code = process.waitFor()
        if (code != 0)
            return null

        return output.readBytes().toList()
    }

    fun update() {
        path.createDirectories()

        val media = path.walk()
            .filter { it.isRegularFile() }
            .mapNotNull {
                val samples = getSamples(it)?:
                    return@mapNotNull null

                val name = it.toString().replace(path.toString(), "")
                val cover = getCover(it)

                MediaEntity(it, name, samples, cover)
            }.toSet()

        repository.clear()
        repository.addAll(media)
    }

}