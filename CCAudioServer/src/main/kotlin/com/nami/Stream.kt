package com.nami

data class Stream(
    val chunkSizeInBytes: Int,
    val chunks: List<ByteArray>,
    val totalBytes: Int,
)