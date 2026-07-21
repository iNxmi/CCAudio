package com.nami.ccaudio.service

import com.nami.ccaudio.entity.MediaEntity
import com.nami.ccaudio.repository.MediaRepository
import java.nio.file.Path
import kotlin.io.path.createDirectories
import kotlin.io.path.isRegularFile
import kotlin.io.path.walk

class MediaService(
    private val repository: MediaRepository,
    private val path: Path
) {

    init {
        update()
    }

    fun update() {
        path.createDirectories()

        val media = path.walk()
            .filter { it.isRegularFile() }
            .map {
                val name = it.toString().replace(path.toString(), "")
                MediaEntity(it, name)
            }.toSet()

        repository.clear()
        repository.addAll(media)
    }

}