import SwiftUI

/// The two notification footprints.
///
/// `classic` is the larger card with the device artwork; `apple` is the compact one
/// that sits under the status item. Both render ``NotificationCard`` — only the icon
/// size, width cap and corner radius change, so a style choice can never leave one of
/// them missing a field the other has.
struct NotificationStyleView: View {

    let notification: DeviceNotification
    let style: NotificationStyle

    var body: some View {
        switch style {
        case .classic:
            NotificationCard(
                notification: notification,
                iconSize: 40,
                maxWidth: 300,
                cornerRadius: 22,
                spacing: 12
            )

        case .apple:
            NotificationCard(
                notification: notification,
                iconSize: 30,
                maxWidth: 280,
                cornerRadius: 18,
                spacing: 12
            )
        }
    }
}
