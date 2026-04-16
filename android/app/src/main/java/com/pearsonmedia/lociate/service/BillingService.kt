package com.pearsonmedia.lociate.service

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.pearsonmedia.lociate.domain.model.SubscriptionTier
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

@Singleton
class BillingService @Inject constructor(
    @ApplicationContext private val context: Context
) : PurchasesUpdatedListener {

    companion object {
        // Product IDs matching iOS RevenueCat configuration
        const val PREMIUM_MONTHLY = "premium_monthly"
        const val PREMIUM_YEARLY = "premium_yearly"
        const val FAMILY_MONTHLY = "family_monthly"
        const val FAMILY_YEARLY = "family_yearly"
        const val LIFETIME_INDIVIDUAL = "lifetime_individual"
        const val LIFETIME_FAMILY = "lifetime_family"

        val SUBSCRIPTION_PRODUCTS = listOf(
            PREMIUM_MONTHLY, PREMIUM_YEARLY, FAMILY_MONTHLY, FAMILY_YEARLY
        )
        val INAPP_PRODUCTS = listOf(LIFETIME_INDIVIDUAL, LIFETIME_FAMILY)
    }

    private val _currentTier = MutableStateFlow(SubscriptionTier.FREE)
    val currentTier: StateFlow<SubscriptionTier> = _currentTier.asStateFlow()

    private val _products = MutableStateFlow<List<ProductDetails>>(emptyList())
    val products: StateFlow<List<ProductDetails>> = _products.asStateFlow()

    private val _purchaseResult = MutableStateFlow<PurchaseResult?>(null)
    val purchaseResult: StateFlow<PurchaseResult?> = _purchaseResult.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases()
        .build()

    private var isConnected = false

    fun connect() {
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    isConnected = true
                    queryProducts()
                    queryPurchases()
                }
            }

            override fun onBillingServiceDisconnected() {
                isConnected = false
            }
        })
    }

    fun queryProducts() {
        // Query subscriptions
        val subParams = QueryProductDetailsParams.newBuilder()
            .setProductList(
                SUBSCRIPTION_PRODUCTS.map { productId ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                }
            )
            .build()

        billingClient.queryProductDetailsAsync(subParams) { result, productDetails ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                val allProducts = productDetails.toMutableList()

                // Also query in-app (lifetime)
                val inappParams = QueryProductDetailsParams.newBuilder()
                    .setProductList(
                        INAPP_PRODUCTS.map { productId ->
                            QueryProductDetailsParams.Product.newBuilder()
                                .setProductId(productId)
                                .setProductType(BillingClient.ProductType.INAPP)
                                .build()
                        }
                    )
                    .build()

                billingClient.queryProductDetailsAsync(inappParams) { inappResult, inappProducts ->
                    if (inappResult.responseCode == BillingClient.BillingResponseCode.OK) {
                        allProducts.addAll(inappProducts)
                    }
                    _products.value = allProducts
                }
            }
        }
    }

    fun queryPurchases() {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                val activePurchase = purchases.firstOrNull {
                    it.purchaseState == Purchase.PurchaseState.PURCHASED
                }

                _currentTier.value = when {
                    activePurchase?.products?.any {
                        it.contains("family")
                    } == true -> SubscriptionTier.FAMILY
                    activePurchase?.products?.any {
                        it.contains("premium") || it.contains("lifetime_individual")
                    } == true -> SubscriptionTier.PREMIUM
                    else -> SubscriptionTier.FREE
                }

                // Also check in-app purchases for lifetime
                val inappParams = QueryPurchasesParams.newBuilder()
                    .setProductType(BillingClient.ProductType.INAPP)
                    .build()

                billingClient.queryPurchasesAsync(inappParams) { _, inappPurchases ->
                    val lifetimePurchase = inappPurchases.firstOrNull {
                        it.purchaseState == Purchase.PurchaseState.PURCHASED
                    }
                    if (lifetimePurchase != null) {
                        _currentTier.value = when {
                            lifetimePurchase.products.any { it.contains("family") } -> SubscriptionTier.FAMILY
                            else -> SubscriptionTier.PREMIUM
                        }
                    }
                }
            }
        }
    }

    fun launchPurchaseFlow(activity: Activity, productDetails: ProductDetails) {
        val offerToken = productDetails.subscriptionOfferDetails?.firstOrNull()?.offerToken

        val productDetailsParams = if (offerToken != null) {
            BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(productDetails)
                .setOfferToken(offerToken)
                .build()
        } else {
            BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(productDetails)
                .build()
        }

        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productDetailsParams))
            .build()

        billingClient.launchBillingFlow(activity, flowParams)
    }

    fun restorePurchases() {
        _isLoading.value = true
        queryPurchases()
        _isLoading.value = false
        _purchaseResult.value = PurchaseResult.Restored
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases?.forEach { purchase ->
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        acknowledgePurchase(purchase)
                    }
                }
                queryPurchases()
                _purchaseResult.value = PurchaseResult.Success
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                _purchaseResult.value = PurchaseResult.Cancelled
            }
            else -> {
                _purchaseResult.value = PurchaseResult.Error(result.debugMessage)
            }
        }
    }

    private fun acknowledgePurchase(purchase: Purchase) {
        if (purchase.isAcknowledged) return
        val params = com.android.billingclient.api.AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        billingClient.acknowledgePurchase(params) { }
    }

    fun clearPurchaseResult() {
        _purchaseResult.value = null
    }

    fun disconnect() {
        billingClient.endConnection()
    }

    fun getProductPrice(productId: String): String? {
        val product = _products.value.find { it.productId == productId }
        return product?.subscriptionOfferDetails?.firstOrNull()
            ?.pricingPhases?.pricingPhaseList?.firstOrNull()?.formattedPrice
            ?: product?.oneTimePurchaseOfferDetails?.formattedPrice
    }
}

sealed class PurchaseResult {
    data object Success : PurchaseResult()
    data object Cancelled : PurchaseResult()
    data object Restored : PurchaseResult()
    data class Error(val message: String) : PurchaseResult()
}
