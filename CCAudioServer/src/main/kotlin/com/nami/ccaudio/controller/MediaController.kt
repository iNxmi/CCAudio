package com.nami.ccaudio.controller

import com.nami.ccaudio.dto.media.GetMedia
import com.nami.ccaudio.repository.MediaRepository
import com.nami.ccaudio.service.MediaService
import com.nami.ccaudio.toStringImage
import io.ktor.http.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import java.time.Duration

fun Route.mediaRoutes(service: MediaService, repository: MediaRepository) {

    get("/api/media") {
        val dto = repository.getAll().withIndex().map { (index, entity) ->
            GetMedia(index, entity)
        }
        call.respond(HttpStatusCode.OK, dto)
    }

    get("/api/media/{index}") {
        val index = call.parameters["index"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val entity = repository.getByIndex(index)
            ?: return@get call.respond(HttpStatusCode.NotFound)

        val dto = GetMedia(index, entity)
        call.respond(HttpStatusCode.OK, dto)
    }

    get("/api/media/{index_media}/chunk/{index_chunk}") {
        val indexMedia = call.parameters["index_media"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val indexChunk = call.parameters["index_chunk"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val samplesPerChunk = call.request.queryParameters["samples_per_chunk"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val entity = repository.getByIndex(indexMedia)
            ?: return@get call.respond(HttpStatusCode.NotFound)

        val chunk = entity.getChunk(indexChunk, samplesPerChunk)
        call.respond(HttpStatusCode.OK, chunk)
    }

    get("/api/media/{index}/cover") {
        val indexMedia = call.parameters["index"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val entity = repository.getByIndex(indexMedia)
            ?: return@get call.respond(HttpStatusCode.NotFound)

        val width = call.request.queryParameters["width"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val height = call.request.queryParameters["height"]?.toIntOrNull()
            ?: return@get call.respond(HttpStatusCode.BadRequest)

        val image = entity.cover
            ?: return@get call.respond(HttpStatusCode.NotFound)

        val imageString = image.toStringImage(width, height)
        call.respond(HttpStatusCode.OK, imageString)
    }

    post("/api/media/reload") {
        val timeStart = System.currentTimeMillis()
        service.update()
        val timeEnd = System.currentTimeMillis()

        val duration = Duration.ofMillis(timeEnd - timeStart)
        val dto = mapOf("duration_in_seconds" to duration.toSeconds())
        call.respond(HttpStatusCode.OK, dto)
    }

}