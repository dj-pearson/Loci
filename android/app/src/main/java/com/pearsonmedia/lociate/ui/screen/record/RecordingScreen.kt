package com.pearsonmedia.lociate.ui.screen.record

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pearsonmedia.lociate.domain.model.LocusCategory
import com.pearsonmedia.lociate.ui.component.CategorySelector
import com.pearsonmedia.lociate.ui.component.AudioWaveform
import com.pearsonmedia.lociate.ui.component.HeroRecordButton

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingScreen(
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
    viewModel: RecordingViewModel = hiltViewModel()
) {
    val isRecording by viewModel.isRecording.collectAsState()
    val amplitude by viewModel.amplitude.collectAsState()
    val transcription by viewModel.transcription.collectAsState()
    val partialResult by viewModel.partialResult.collectAsState()
    val showPostRecording by viewModel.showPostRecording.collectAsState()
    val selectedCategory by viewModel.selectedCategory.collectAsState()
    val isSaving by viewModel.isSaving.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        // Close button
        IconButton(
            onClick = {
                if (isRecording) viewModel.stopRecording()
                viewModel.discardRecording()
                onDismiss()
            },
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(16.dp)
        ) {
            Icon(Icons.Default.Close, contentDescription = "Close")
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // Transcription display
            Text(
                text = transcription.ifEmpty { partialResult.ifEmpty { "Your words will appear here..." } },
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
                color = if (transcription.isEmpty() && partialResult.isEmpty()) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Waveform
            if (isRecording) {
                AudioWaveform(
                    amplitude = amplitude,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(60.dp)
                )
            }

            Spacer(modifier = Modifier.height(48.dp))

            // Premium hero record button (US-166)
            HeroRecordButton(
                isRecording = isRecording,
                amplitude = amplitude,
                onClick = {
                    if (isRecording) {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = if (isRecording) "Tap to stop" else "Tap to record",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Post-recording bottom sheet
        if (showPostRecording) {
            ModalBottomSheet(
                onDismissRequest = {
                    viewModel.discardRecording()
                    onDismiss()
                },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ) {
                PostRecordingContent(
                    selectedCategory = selectedCategory,
                    onCategorySelected = { viewModel.selectCategory(it) },
                    isSaving = isSaving,
                    onSave = { viewModel.saveLocus(onSaved) },
                    onDiscard = {
                        viewModel.discardRecording()
                        onDismiss()
                    }
                )
            }
        }
    }
}

@Composable
private fun PostRecordingContent(
    selectedCategory: LocusCategory,
    onCategorySelected: (LocusCategory) -> Unit,
    isSaving: Boolean,
    onSave: () -> Unit,
    onDiscard: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Save Voice Note",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Category",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(8.dp))

        CategorySelector(
            selectedCategory = selectedCategory,
            onCategorySelected = onCategorySelected
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onSave,
            enabled = !isSaving,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (isSaving) "Saving..." else "Save Locus")
        }

        Spacer(modifier = Modifier.height(8.dp))

        Button(
            onClick = onDiscard,
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.error
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Discard")
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}
