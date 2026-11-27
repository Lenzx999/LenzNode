package com.lenznode.app.runtime

import android.content.Context
import android.content.SharedPreferences
import com.lenznode.app.model.AppMode
import com.lenznode.app.model.RemoteProfile
import org.json.JSONArray
import org.json.JSONObject

class AppModeStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getAppMode(): AppMode {
        val raw = prefs.getString(KEY_APP_MODE, AppMode.UNSELECTED.name) ?: AppMode.UNSELECTED.name
        return try {
            AppMode.valueOf(raw)
        } catch (_: Exception) {
            AppMode.UNSELECTED
        }
    }

    fun setAppMode(mode: AppMode) {
        prefs.edit().putString(KEY_APP_MODE, mode.name).apply()
    }

    fun getActiveProfileId(): String? = prefs.getString(KEY_ACTIVE_PROFILE_ID, null)

    fun setActiveProfileId(id: String?) {
        prefs.edit().putString(KEY_ACTIVE_PROFILE_ID, id).apply()
    }

    fun getSavedProfiles(): List<RemoteProfile> {
        val raw = prefs.getString(KEY_REMOTE_PROFILES, "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val id = obj.optString("id")
                    val baseUrl = obj.optString("baseUrl")
                    val token = obj.optString("token")
                    if (id.isNotBlank() && baseUrl.isNotBlank()) {
                        add(
                            RemoteProfile(
                                id = id,
                                name = obj.optString("name").ifBlank { baseUrl },
                                baseUrl = baseUrl,
                                token = token,
                                lastConnectedMs = obj.optLong("lastConnectedMs", 0L)
                            )
                        )
                    }
                }
            }.sortedByDescending { it.lastConnectedMs }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveProfile(profile: RemoteProfile) {
        val updated = getSavedProfiles().filterNot {
            it.id == profile.id || it.baseUrl.equals(profile.baseUrl, ignoreCase = true)
        }.toMutableList()
        updated.add(0, profile)

        val arr = JSONArray()
        for (item in updated.take(10)) {
            arr.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("name", item.name)
                    put("baseUrl", item.baseUrl)
                    put("token", item.token)
                    put("lastConnectedMs", item.lastConnectedMs)
                }
            )
        }
        prefs.edit()
            .putString(KEY_REMOTE_PROFILES, arr.toString())
            .putString(KEY_ACTIVE_PROFILE_ID, profile.id)
            .apply()
    }

    fun deleteProfile(id: String) {
        val remaining = getSavedProfiles().filterNot { it.id == id }
        val arr = JSONArray()
        for (item in remaining) {
            arr.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("name", item.name)
                    put("baseUrl", item.baseUrl)
                    put("token", item.token)
                    put("lastConnectedMs", item.lastConnectedMs)
                }
            )
        }
        val editor = prefs.edit().putString(KEY_REMOTE_PROFILES, arr.toString())
        if (getActiveProfileId() == id) {
            editor.remove(KEY_ACTIVE_PROFILE_ID)
        }
        editor.apply()
    }

    fun getActiveProfile(): RemoteProfile? {
        val profiles = getSavedProfiles()
        val activeId = getActiveProfileId()
        return profiles.firstOrNull { it.id == activeId } ?: profiles.firstOrNull()
    }

    companion object {
        private const val PREFS_NAME = "lenznode_app_mode_prefs"
        private const val KEY_APP_MODE = "app_mode"
        private const val KEY_REMOTE_PROFILES = "remote_profiles"
        private const val KEY_ACTIVE_PROFILE_ID = "active_profile_id"
    }
}
