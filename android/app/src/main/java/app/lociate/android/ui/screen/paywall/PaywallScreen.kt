package com.pearsonmedia.lociate.ui.screen.paywall

import android.app.Activity
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.ui.draw.clip
import com.pearsonmedia.lociate.ui.theme.DesignTokens
import com.pearsonmedia.lociate.ui.theme.LociateGradients
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pearsonmedia.lociate.service.BillingService
import com.pearsonmedia.lociate.service.PurchaseResult

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    onBack: () -> Unit,
    viewModel: PaywallViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val currentTier by viewModel.currentTier.collectAsState()
    val purchaseResult by viewModel.purchaseResult.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    LaunchedEffect(purchaseResult) {
        when (purchaseResult) {
            is PurchaseResult.Success -> {
                snackbarHostState.showSnackbar("Purchase successful! Welcome to Premium.")
                viewModel.clearPurchaseResult()
            }
            is PurchaseResult.Restored -> {
                snackbarHostState.showSnackbar("Purchases restored.")
                viewModel.clearPurchaseResult()
            }
            is PurchaseResult.Error -> {
                snackbarHostState.showSnackbar("Purchase failed: ${(purchaseResult as PurchaseResult.Error).message}")
                viewModel.clearPurchaseResult()
            }
            else -> {}
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Upgrade") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Premium hero tile (US-170)
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(DesignTokens.Radius.LG))
                    .background(LociateGradients.Premium),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.LocationOn,
                    contentDescription = null,
                    tint = androidx.compose.ui.graphics.Color.White,
                    modifier = Modifier.size(48.dp)
                )
            }
            Spacer(Modifier.height(DesignTokens.Space.MD))
            Text(
                "Unlock the Full Lociate Experience",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(DesignTokens.Space.XS))
            Text(
                "Pin more memories, sync everywhere, and share with family.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(Modifier.height(16.dp))

            // Monthly/Yearly toggle
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = !uiState.isYearly,
                    onClick = { viewModel.setYearly(false) },
                    label = { Text("Monthly") }
                )
                FilterChip(
                    selected = uiState.isYearly,
                    onClick = { viewModel.setYearly(true) },
                    label = { Text("Yearly (Save 37%)") }
                )
            }

            Spacer(Modifier.height(24.dp))

            // Free tier
            TierCard(
                title = "Free",
                price = "Free",
                features = listOf(
                    FeatureItem("Up to 10 loci", true),
                    FeatureItem("Voice recording", true),
                    FeatureItem("On-device transcription", true),
                    FeatureItem("AI categorization", false),
                    FeatureItem("Cloud sync", false),
                    FeatureItem("Widget", false),
                    FeatureItem("Search", false),
                    FeatureItem("Family sharing", false)
                ),
                isCurrentPlan = currentTier == com.pearsonmedia.lociate.domain.model.SubscriptionTier.FREE,
                onSelect = {}
            )

            Spacer(Modifier.height(12.dp))

            // Premium tier
            val premiumId = if (uiState.isYearly) BillingService.PREMIUM_YEARLY else BillingService.PREMIUM_MONTHLY
            TierCard(
                title = "Premium",
                price = viewModel.getPrice(premiumId),
                features = listOf(
                    FeatureItem("Unlimited loci", true),
                    FeatureItem("Voice recording", true),
                    FeatureItem("On-device transcription", true),
                    FeatureItem("AI categorization", true),
                    FeatureItem("Cloud sync", true),
                    FeatureItem("Widget", true),
                    FeatureItem("Search", true),
                    FeatureItem("Family sharing", false)
                ),
                isCurrentPlan = currentTier == com.pearsonmedia.lociate.domain.model.SubscriptionTier.PREMIUM,
                isRecommended = true,
                onSelect = {
                    (context as? Activity)?.let { activity ->
                        viewModel.purchase(activity, premiumId)
                    }
                }
            )

            Spacer(Modifier.height(12.dp))

            // Family tier
            val familyId = if (uiState.isYearly) BillingService.FAMILY_YEARLY else BillingService.FAMILY_MONTHLY
            TierCard(
                title = "Family",
                price = viewModel.getPrice(familyId),
                features = listOf(
                    FeatureItem("Unlimited loci", true),
                    FeatureItem("Voice recording", true),
                    FeatureItem("On-device transcription", true),
                    FeatureItem("AI categorization", true),
                    FeatureItem("Cloud sync", true),
                    FeatureItem("Widget", true),
                    FeatureItem("Search", true),
                    FeatureItem("Family sharing (up to 6)", true)
                ),
                isCurrentPlan = currentTier == com.pearsonmedia.lociate.domain.model.SubscriptionTier.FAMILY,
                onSelect = {
                    (context as? Activity)?.let { activity ->
                        viewModel.purchase(activity, familyId)
                    }
                }
            )

            Spacer(Modifier.height(24.dp))

            // Restore purchases
            OutlinedButton(onClick = { viewModel.restorePurchases() }) {
                Text("Restore Purchases")
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

data class FeatureItem(val name: String, val included: Boolean)

@Composable
private fun TierCard(
    title: String,
    price: String,
    features: List<FeatureItem>,
    isCurrentPlan: Boolean,
    isRecommended: Boolean = false,
    onSelect: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        border = if (isRecommended) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
        elevation = CardDefaults.cardElevation(defaultElevation = if (isRecommended) 4.dp else 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            if (isRecommended) {
                Text(
                    "RECOMMENDED",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom
            ) {
                Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(price, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            }

            Spacer(Modifier.height(12.dp))

            features.forEach { feature ->
                Row(
                    modifier = Modifier.padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        if (feature.included) Icons.Default.Check else Icons.Default.Close,
                        contentDescription = null,
                        tint = if (feature.included) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.padding(end = 8.dp)
                    )
                    Text(
                        feature.name,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (feature.included) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    )
                }
            }

            Spacer(Modifier.height(12.dp))

            if (isCurrentPlan) {
                OutlinedButton(onClick = {}, modifier = Modifier.fillMaxWidth(), enabled = false) {
                    Text("Current Plan")
                }
            } else if (price != "Free") {
                Button(onClick = onSelect, modifier = Modifier.fillMaxWidth()) {
                    Text("Subscribe")
                }
            }
        }
    }
}
