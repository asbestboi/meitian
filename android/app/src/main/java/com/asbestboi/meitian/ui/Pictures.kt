package com.asbestboi.meitian.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Online
import kotlinx.coroutines.launch
import uniffi.meitian_core.BattlePlayer
import uniffi.meitian_core.OnlineProfile
import uniffi.meitian_core.avatarColor
import uniffi.meitian_core.initials

/** A player's profile picture, or their initials on a colour of their own. [path] is the server's, "" for none. */
@Composable
fun Picture(id: String, name: String, path: String, size: Dp = 46.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).clip(CircleShape).background(hexColor(avatarColor(id))), contentAlignment = Alignment.Center) {
        Text(initials(name), fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.ExtraBold, color = Color.White, maxLines = 1)
        if (path.isNotEmpty()) AsyncImage(Online.baseUrl + path, "$name's picture", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    }
}

@Composable
fun Avatar(p: OnlineProfile?, size: Dp = 46.dp) = Picture(p?.id.orEmpty(), p?.nickname.orEmpty(), p?.avatar.orEmpty(), size)

@Composable
fun BattlePicture(p: BattlePlayer, size: Dp = 46.dp, modifier: Modifier = Modifier) = Picture(p.id, p.name, p.profile?.avatar.orEmpty(), size, modifier)

/** The learner's own picture. */
@Composable
fun MyPicture(size: Dp, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val me = Online.profile
    Picture(me?.id ?: app.arena.playerId, app.profile.name.ifBlank { me?.nickname ?: "Learner" }, me?.avatar.orEmpty(), size, modifier)
}

/** Picks and uploads a profile picture (creating the online profile from the learner's name if needed). */
class PicturePicker(val busy: Boolean, val note: String?, val pick: () -> Unit)

@Composable
fun rememberPicturePicker(name: String? = null, onDone: () -> Unit = {}): PicturePicker {
    val app = LocalApp.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            note = runCatching {
                Online.init(ctx)
                Online.ensureAccount(name ?: app.profile.name)
                Online.uploadAvatar(ctx, uri)
                onDone()
                "Looking good ✦"
            }.getOrElse { it.message ?: "That didn't work, try again later." }
            busy = false
        }
    }
    return PicturePicker(busy, note) { launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
}

fun hexColor(hex: String): Color = runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrDefault(Color.White)
