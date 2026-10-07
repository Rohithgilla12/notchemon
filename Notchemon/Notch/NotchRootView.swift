import SwiftUI

struct NotchRootView: View {
    let presentation: NotchPresentation

    var body: some View {
        if let metrics = presentation.metrics {
            let expanded = presentation.isExpanded
            let size = expanded ? metrics.panelSize : metrics.notchSize
            ZStack(alignment: .topLeading) {
                NotchShape(bottomRadius: expanded ? 22 : 9)
                    .fill(.black)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, alignment: .top)

                Circle()
                    .fill(.orange)
                    .frame(width: metrics.spriteFrame(expanded: expanded).width, height: metrics.spriteFrame(expanded: expanded).height)
                    .offset(x: metrics.spriteFrame(expanded: expanded).minX, y: metrics.spriteFrame(expanded: expanded).minY)

                NotchShape(bottomRadius: 9)
                    .fill(.black)
                    .frame(width: metrics.notchSize.width, height: metrics.notchSize.height)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .topLeading)
        }
    }
}
