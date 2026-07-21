package com.nami.ccaudio

import org.slf4j.LoggerFactory
import java.awt.Color
import java.awt.Image
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.nio.file.Path
import kotlin.io.path.createTempFile
import kotlin.io.path.deleteIfExists

inline fun <T> withTemporaryFile(suffix: String = ".tmp", block: (Path) -> T): T {
    val path = createTempFile("ccaudio_server_", suffix)
    return try {
        block(path)
    } finally {
        if (!path.deleteIfExists())
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

fun Image.toStringImage(width: Int, height: Int): String {
    val resizedImage = BufferedImage(width, height, BufferedImage.TYPE_INT_RGB)
    val graphics = resizedImage.createGraphics()
    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
    graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
    graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
    graphics.drawImage(this, 0, 0, width, height, null)
    graphics.dispose()

    val result = StringBuilder()
    for (y in 0 until height) {
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

fun LoggerFactory.getLogger(`class`: Class<*>) = LoggerFactory.getLogger(`class`.name)