package com.nami.ccaudio.entity

import ch.qos.logback.classic.Logger
import com.nami.ccaudio.withTemporaryFile
import org.slf4j.LoggerFactory
import java.awt.image.BufferedImage
import java.nio.file.Path
import javax.imageio.ImageIO
import kotlin.io.path.absolutePathString
import kotlin.io.path.readBytes
import kotlin.math.min

data class MediaEntity(
    val path: Path,
    val name: String
) {

    val logger: Logger = LoggerFactory.getLogger(this.javaClass) as Logger

    val samples: List<Byte> by lazy {
        logger.info("Loading Samples: $path")
        getSamples(path)
    }

    val cover: BufferedImage? by lazy {
        logger.info("Loading Cover: $path")
        getCover(path)
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

    private fun getSamples(input: Path): List<Byte> = withTemporaryFile(".pcm") { output ->
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
            throw Exception("something went wrong")

        return output.readBytes().toList()
    }

    fun getChunk(index: Int, numberOfSamples: Int): List<Byte> {
        val start = index * numberOfSamples
        val end = min((index + 1) * numberOfSamples, samples.size)
        return samples.subList(start, end)
    }

}