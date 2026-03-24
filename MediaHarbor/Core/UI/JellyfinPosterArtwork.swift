import SwiftUI
import SDWebImage

struct JellyfinPosterArtwork<Overlay: View>: View {
    let url: URL?
    let height: CGFloat
    let cornerRadius: CGFloat
    let symbolName: String
    let overlayAlignment: Alignment
    let overlay: Overlay

    init(
        url: URL?,
        height: CGFloat,
        cornerRadius: CGFloat,
        symbolName: String = "film.stack.fill",
        overlayAlignment: Alignment = .bottomLeading,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.url = url
        self.height = height
        self.cornerRadius = cornerRadius
        self.symbolName = symbolName
        self.overlayAlignment = overlayAlignment
        self.overlay = overlay()
    }

    var body: some View {
        ZStack(alignment: overlayAlignment) {
            placeholderBackground

            JellyfinPosterImageView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.58),
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            overlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.28, blue: 0.38),
                Color(red: 0.12, green: 0.13, blue: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct JellyfinPosterImageView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> JellyfinPosterContainerView {
        let containerView = JellyfinPosterContainerView()
        containerView.imageView.sd_imageIndicator = SDWebImageActivityIndicator.medium
        return containerView
    }

    func updateUIView(_ containerView: JellyfinPosterContainerView, context: Context) {
        let imageView = containerView.imageView

        guard imageView.sd_imageURL != url else {
            return
        }

        guard let url else {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = nil
            return
        }

        imageView.sd_setImage(
            with: url,
            placeholderImage: nil,
            options: [
                .retryFailed,
                .continueInBackground,
                .highPriority,
                .scaleDownLargeImages,
            ]
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: JellyfinPosterContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ uiView: JellyfinPosterContainerView, coordinator: ()) {
        uiView.imageView.sd_cancelCurrentImageLoad()
    }
}

final class JellyfinPosterContainerView: UIView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
