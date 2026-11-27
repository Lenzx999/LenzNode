package com.lenznode.app

import com.lenznode.app.runtime.NativeBridgeJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeBridgeJsonTest {

    @Test
    fun `serializes charging battery telemetry accurately`() {
        val raw = NativeBridgeJson.batteryJson(
            percentage = 84,
            status = "Mengisi Daya",
            plugged = "AC",
            temperatureC = 34.5,
            voltageMv = 4200,
            currentMa = 1500.0,
            isCharging = true
        )
        val parsed = NativeBridgeJson.parseJsonParams(raw)
        assertEquals("84", parsed["percentage"])
        assertEquals("Mengisi Daya", parsed["status"])
        assertEquals("AC", parsed["plugged"])
        assertEquals("34.5", parsed["temperature"])
        assertEquals("4.20 V", parsed["voltage"])
        assertEquals("4.20", parsed["voltageVolts"])
        assertEquals("1.50 A", parsed["current"])
        assertEquals("1500.0", parsed["currentMa"])
        assertEquals("6.30", parsed["watts"])
        assertEquals("6.30", parsed["powerWatts"])
        assertTrue(parsed["powerText"]!!.startsWith("Pengisian: +6.30 W"))
        assertEquals("true", parsed["isCharging"])
    }

    @Test
    fun `serializes thermal telemetry and status thresholds`() {
        val warmRaw = NativeBridgeJson.thermalJson(
            cpuTemp = 64,
            batteryTemp = 37.2,
            cores = listOf(62, 64, null, 60)
        )
        val warmParsed = NativeBridgeJson.parseJsonParams(warmRaw)
        assertEquals("64°C", warmParsed["cpu"])
        assertEquals("64", warmParsed["cpuTemp"])
        assertEquals("37.2°C", warmParsed["battery"])
        assertEquals("37.2", warmParsed["batteryTemp"])
        assertEquals("Hangat", warmParsed["status"])
        assertTrue(warmRaw.contains("\"cores\":[62,64,64,60]"))

        val hotRaw = NativeBridgeJson.thermalJson(cpuTemp = 79, batteryTemp = null)
        val hotParsed = NativeBridgeJson.parseJsonParams(hotRaw)
        assertEquals("Panas", hotParsed["status"])
        assertTrue(hotRaw.contains("\"battery\":null"))
        assertTrue(hotRaw.contains("\"batteryTemp\":null"))
    }

    @Test
    fun `serializes control responses and parses query and json parameters`() {
        val torchParsed = NativeBridgeJson.parseJsonParams(
            NativeBridgeJson.torchJson(true, true, "Senter HP dinyalakan.")
        )
        assertEquals("true", torchParsed["ok"])
        assertEquals("true", torchParsed["torch"])

        val vibrateParsed = NativeBridgeJson.parseJsonParams(
            NativeBridgeJson.vibrateJson(true, 400, "Getaran dikirim.")
        )
        assertEquals("true", vibrateParsed["ok"])
        assertEquals("400", vibrateParsed["duration"])

        val wakelockParsed = NativeBridgeJson.parseJsonParams(
            NativeBridgeJson.wakelockJson(true, false, "Wake-Lock dinonaktifkan.")
        )
        assertEquals("true", wakelockParsed["ok"])
        assertEquals("false", wakelockParsed["active"])

        val (path, query) = NativeBridgeJson.parseHttpTarget("/torch?state=on&duration=500")
        assertEquals("/torch", path)
        assertEquals("on", query["state"])
        assertEquals("500", query["duration"])

        val bodyParams = NativeBridgeJson.parseJsonParams("""{"enable":true,"duration":350,"note":"halo \"lenz\""}""")
        assertEquals("true", bodyParams["enable"])
        assertEquals("350", bodyParams["duration"])
        assertEquals("halo \"lenz\"", bodyParams["note"])
    }

    @Test
    fun `ignores qualcomm ibat and vbat alarms when scanning battery thermal zones`() {
        assertNull(NativeBridgeJson.parseBatteryThermalTemp("pm6150-ibat-lvl0", -234))
        assertNull(NativeBridgeJson.parseBatteryThermalTemp("pm6150-ibat-lvl1", 78))
        assertNull(NativeBridgeJson.parseBatteryThermalTemp("pm6150-vbat-lvl0", 4035))
        assertEquals(33.5, NativeBridgeJson.parseBatteryThermalTemp("battery", 33500)!!, 0.01)
        assertEquals(34.2, NativeBridgeJson.parseBatteryThermalTemp("batt_therm", 342)!!, 0.01)
        assertEquals(31.0, NativeBridgeJson.parseBatteryThermalTemp("bms", 31000)!!, 0.01)
    }
}
