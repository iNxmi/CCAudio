package com.nami.ccaudio.entity

import java.awt.image.BufferedImage
import java.nio.file.Path
import kotlin.math.min

data class MediaEntity(
    val path: Path,
    val name: String,
    val samples: List<Byte>,
    val cover: BufferedImage?
) {

    fun getChunk(index: Int, numberOfSamples: Int): List<Byte> {
        val start = index * numberOfSamples
        val end = min((index + 1) * numberOfSamples, samples.size)
        return samples.subList(start, end)
    }

}