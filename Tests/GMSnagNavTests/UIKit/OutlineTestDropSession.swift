#if os(iOS)
  import UIKit

  @MainActor
  final class OutlineTestDropSession: NSObject, UIDropSession {
    var items: [UIDragItem] = []
    var allowsMoveOperation = true
    var isRestrictedToDraggingApplication = true
    var localDragSession: (any UIDragSession)?
    nonisolated let progress = Progress(totalUnitCount: 0)
    var progressIndicatorStyle = UIDropSessionProgressIndicatorStyle.none

    func location(in view: UIView) -> CGPoint { .zero }
    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { true }
    func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
    func loadObjects(
      ofClass aClass: any NSItemProviderReading.Type,
      completion: @escaping ([any NSItemProviderReading]) -> Void
    ) -> Progress {
      completion([])
      return progress
    }
  }

#endif
