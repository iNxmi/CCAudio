package com.nami.ccaudio.dto.media

import com.nami.ccaudio.entity.MediaEntity
import java.nio.file.Path

data class GetMedia(
    val index: Int,

    val name: String,
    val path: Path,
    val numberOfSamples: Int,

    val hasCover: Boolean
) {

    constructor(index: Int, entity: MediaEntity) : this(
        index = index,

        name = entity.name,
        path = entity.path,
        numberOfSamples = entity.samples.size,

        hasCover = entity.cover != null
    )

}