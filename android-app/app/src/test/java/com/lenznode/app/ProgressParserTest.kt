package com.lenznode.app

import com.lenznode.app.model.ProgressParser
import com.lenznode.app.model.ServerPhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ProgressParserTest {

    @Test
    fun `parses basic progress line for rootfs stage`() {
        val result = ProgressParser.parseLine("[PROGRESS:18] Mengekstrak rootfs Ubuntu 22.04...")
        assertNotNull(result)
        assertEquals(18, result!!.progress)
        assertEquals("Mengekstrak rootfs Ubuntu 22.04...", result.message)
        assertEquals(ServerPhase.INSTALLING_ROOTFS, result.suggestedPhase)
    }

    @Test
    fun `strips ansi codes and detects dependency stage`() {
        val raw = "\u001B[1;33m[PROGRESS:55]\u001B[0m Memasang Node.js & OpenSSH..."
        val result = ProgressParser.parseLine(raw)
        assertNotNull(result)
        assertEquals(55, result!!.progress)
        assertEquals("Memasang Node.js & OpenSSH...", result.message)
        assertEquals(ServerPhase.INSTALLING_DEPS, result.suggestedPhase)
    }

    @Test
    fun `clamps percentage above 100 and detects starting stage`() {
        val result = ProgressParser.parseLine("[PROGRESS:120] Menyalakan server...")
        assertNotNull(result)
        assertEquals(100, result!!.progress)
        assertEquals(ServerPhase.STARTING, result.suggestedPhase)
    }

    @Test
    fun `returns null for regular log lines without progress marker`() {
        assertNull(ProgressParser.parseLine("Get:1 http://ports.ubuntu.com/ubuntu-ports jammy InRelease"))
        assertNull(ProgressParser.parseLine(""))
    }
}
