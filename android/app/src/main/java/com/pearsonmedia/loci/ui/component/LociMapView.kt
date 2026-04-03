package com.pearsonmedia.loci.ui.component

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import com.pearsonmedia.loci.domain.model.Locus

@Composable
fun LociMapView(
    loci: List<Locus>,
    onLocusClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val defaultPosition = if (loci.isNotEmpty()) {
        LatLng(loci.first().latitude, loci.first().longitude)
    } else {
        LatLng(37.7749, -122.4194) // San Francisco default
    }

    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(defaultPosition, 14f)
    }

    GoogleMap(
        modifier = modifier,
        cameraPositionState = cameraPositionState
    ) {
        loci.forEach { locus ->
            Marker(
                state = MarkerState(
                    position = LatLng(locus.latitude, locus.longitude)
                ),
                title = locus.locationName ?: locus.category.displayName,
                snippet = locus.transcription.take(50),
                onClick = {
                    onLocusClick(locus.id.toString())
                    true
                }
            )
        }
    }
}
