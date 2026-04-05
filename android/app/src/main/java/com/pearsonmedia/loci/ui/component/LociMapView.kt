package com.pearsonmedia.loci.ui.component

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapType
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import com.pearsonmedia.loci.domain.model.Locus
import com.pearsonmedia.loci.domain.model.LocusCategory

/**
 * Premium styled map (US-167).
 *
 * Each marker is tinted with a category-specific hue using
 * [BitmapDescriptorFactory.defaultMarker] so Loci notes are visually
 * distinguishable at a glance without shipping custom raster assets.
 *
 * POI clutter is suppressed and indoor mode is disabled to keep the map
 * focused on the user's saved loci.
 */
@Composable
fun LociMapView(
    loci: List<Locus>,
    onLocusClick: (String) -> Unit,
    modifier: Modifier = Modifier,
    selectedLocusId: String? = null
) {
    val defaultPosition = if (loci.isNotEmpty()) {
        LatLng(loci.first().latitude, loci.first().longitude)
    } else {
        LatLng(37.7749, -122.4194) // San Francisco default
    }

    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(defaultPosition, 14f)
    }

    val mapProperties = remember {
        MapProperties(
            mapType = MapType.NORMAL,
            isBuildingEnabled = true,
            isIndoorEnabled = false,
            isTrafficEnabled = false
        )
    }

    val uiSettings = remember {
        MapUiSettings(
            compassEnabled = true,
            myLocationButtonEnabled = false,
            mapToolbarEnabled = false,
            zoomControlsEnabled = false,
            rotationGesturesEnabled = true,
            tiltGesturesEnabled = true
        )
    }

    GoogleMap(
        modifier = modifier,
        cameraPositionState = cameraPositionState,
        properties = mapProperties,
        uiSettings = uiSettings
    ) {
        loci.forEach { locus ->
            val isSelected = locus.id.toString() == selectedLocusId
            Marker(
                state = MarkerState(
                    position = LatLng(locus.latitude, locus.longitude)
                ),
                title = locus.locationName ?: locus.category.displayName,
                snippet = locus.transcription.take(50),
                icon = BitmapDescriptorFactory.defaultMarker(locus.category.markerHue()),
                zIndex = if (isSelected) 10f else 1f,
                onClick = {
                    onLocusClick(locus.id.toString())
                    true
                }
            )
        }
    }
}

/**
 * Maps each category to an approximate hue on Google Maps' default marker
 * hue scale (0–360). Values are hand-picked to match the Compose Color
 * tokens in [LocusCategory] so the map matches the rest of the app.
 */
private fun LocusCategory.markerHue(): Float = when (this) {
    LocusCategory.GENERAL -> BitmapDescriptorFactory.HUE_BLUE       // 240
    LocusCategory.FOOD -> BitmapDescriptorFactory.HUE_RED           // 0
    LocusCategory.SHOPPING -> BitmapDescriptorFactory.HUE_VIOLET    // 270
    LocusCategory.PARKING -> BitmapDescriptorFactory.HUE_AZURE      // 210
    LocusCategory.HEALTH -> BitmapDescriptorFactory.HUE_GREEN       // 120
    LocusCategory.TRAVEL -> BitmapDescriptorFactory.HUE_ORANGE      // 30
    LocusCategory.TIP -> BitmapDescriptorFactory.HUE_YELLOW         // 60
    LocusCategory.WARNING -> BitmapDescriptorFactory.HUE_ORANGE     // 30
    LocusCategory.HOME -> BitmapDescriptorFactory.HUE_ROSE          // 330
    LocusCategory.OUTDOOR -> BitmapDescriptorFactory.HUE_CYAN       // 180
}
