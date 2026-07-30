import SwiftUI
import WidgetKit

/// US-187: entry point for the `LociateWidget` app extension.
///
/// Without a `@main WidgetBundle` the extension has no executable entry point,
/// so `NearbyLociWidget` never gets registered with WidgetKit and the widget
/// does not appear in the gallery.
@main
struct LociateWidgetBundle: WidgetBundle {
    var body: some Widget {
        NearbyLociWidget()
    }
}
