package app.lociate.android.ui.screen.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import com.android.billingclient.api.ProductDetails
import app.lociate.android.domain.model.SubscriptionTier
import app.lociate.android.service.BillingService
import app.lociate.android.service.PurchaseResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

data class PaywallUiState(
    val selectedPlan: String = BillingService.PREMIUM_MONTHLY,
    val isYearly: Boolean = false
)

@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val billingService: BillingService
) : ViewModel() {

    val products: StateFlow<List<ProductDetails>> = billingService.products
    val currentTier: StateFlow<SubscriptionTier> = billingService.currentTier
    val purchaseResult: StateFlow<PurchaseResult?> = billingService.purchaseResult
    val isLoading: StateFlow<Boolean> = billingService.isLoading

    private val _uiState = MutableStateFlow(PaywallUiState())
    val uiState: StateFlow<PaywallUiState> = _uiState.asStateFlow()

    init {
        billingService.connect()
    }

    fun setYearly(yearly: Boolean) {
        _uiState.value = _uiState.value.copy(isYearly = yearly)
    }

    fun selectPlan(productId: String) {
        _uiState.value = _uiState.value.copy(selectedPlan = productId)
    }

    fun purchase(activity: Activity, productId: String) {
        val product = products.value.find { it.productId == productId } ?: return
        billingService.launchPurchaseFlow(activity, product)
    }

    fun restorePurchases() {
        billingService.restorePurchases()
    }

    fun clearPurchaseResult() {
        billingService.clearPurchaseResult()
    }

    fun getPrice(productId: String): String {
        return billingService.getProductPrice(productId) ?: when (productId) {
            BillingService.PREMIUM_MONTHLY -> "$3.99/mo"
            BillingService.PREMIUM_YEARLY -> "$29.99/yr"
            BillingService.FAMILY_MONTHLY -> "$5.99/mo"
            BillingService.FAMILY_YEARLY -> "$44.99/yr"
            BillingService.LIFETIME_INDIVIDUAL -> "$59.99"
            BillingService.LIFETIME_FAMILY -> "$89.99"
            else -> ""
        }
    }
}
