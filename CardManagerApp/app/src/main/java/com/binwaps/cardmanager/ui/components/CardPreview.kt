package com.binwaps.cardmanager.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import com.binwaps.cardmanager.data.Store
import com.binwaps.cardmanager.model.CardTemplate
import com.binwaps.cardmanager.model.UserEntry
import com.binwaps.cardmanager.render.CardRenderer

val sampleUser = UserEntry(
    username = "user1234",
    password = "8642",
    profile = "شهري 10 جيجا",
    price = "500",
    validity = "30d",
    serial = "0001",
)

@Composable
fun CardPreview(
    template: CardTemplate,
    user: UserEntry = sampleUser,
    widthPx: Int = 800,
    modifier: Modifier = Modifier,
) {
    val settings = Store.settings.value
    val bitmap: Bitmap = remember(template, user, widthPx, settings) {
        CardRenderer.render(template, user, settings, widthPx)
    }
    Image(
        bitmap = bitmap.asImageBitmap(),
        contentDescription = null,
        modifier = modifier,
        contentScale = ContentScale.FillWidth,
    )
}
