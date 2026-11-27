package com.lenznode.app

import com.lenznode.app.model.AbiHelper
import org.junit.Assert.assertEquals
import org.junit.Test

class AbiHelperTest {

    @Test
    fun `prefers arm64-v8a when both 64-bit and 32-bit abis are supported`() {
        val abi = AbiHelper.resolvePrimaryAbi(arrayOf("armeabi-v7a", "arm64-v8a", "armeabi"))
        assertEquals("arm64-v8a", abi)
    }

    @Test
    fun `falls back to armeabi-v7a on older 32-bit devices`() {
        val abi = AbiHelper.resolvePrimaryAbi(arrayOf("armeabi-v7a", "armeabi"))
        assertEquals("armeabi-v7a", abi)
    }

    @Test
    fun `falls back to armeabi-v7a when supported abis list is empty`() {
        assertEquals("armeabi-v7a", AbiHelper.resolvePrimaryAbi(emptyArray()))
    }

    @Test
    fun `maps android abis to linux and cloudflared architectures`() {
        assertEquals("arm64", AbiHelper.resolveLinuxArch("arm64-v8a"))
        assertEquals("armhf", AbiHelper.resolveLinuxArch("armeabi-v7a"))
        assertEquals("amd64", AbiHelper.resolveLinuxArch("x86_64"))
        assertEquals("i386", AbiHelper.resolveLinuxArch("x86"))

        assertEquals("arm64", AbiHelper.resolveCloudflaredArch("arm64-v8a"))
        assertEquals("arm", AbiHelper.resolveCloudflaredArch("armeabi-v7a"))
        assertEquals("ubuntu-base-22.04.5-base-arm64.tar.gz", AbiHelper.rootfsTarballName("arm64"))
        assertEquals("ubuntu-base-22.04.5-base-armhf.tar.gz", AbiHelper.rootfsTarballName("armhf"))
    }
}
