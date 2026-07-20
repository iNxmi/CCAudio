package com.nami.ccaudio.repository

import com.nami.ccaudio.entity.MediaEntity

class MediaRepository {

    val cache = sortedSetOf<MediaEntity>(compareBy(String.CASE_INSENSITIVE_ORDER) { it.path.toString() })

    fun clear() = cache.clear()
    fun getByIndex(index: Int) = cache.toList().getOrNull(index)
    fun getAll() = cache.toList()
    fun addAll(collection: Collection<MediaEntity>) = cache.addAll(collection)

}