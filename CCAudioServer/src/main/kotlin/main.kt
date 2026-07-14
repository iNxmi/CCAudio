package com.example

import io.ktor.server.engine.*
import io.ktor.server.application.*

data class Test(val a : Int)

fun main(args: Array<String>) {
    io.ktor.server.netty.EngineMain.main(args)
}
