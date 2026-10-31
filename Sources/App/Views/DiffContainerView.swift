import AppKit

public final class DiffContainerView: NSView {
    public let leftEditor: DiffEditorView
    public let rightEditor: DiffEditorView
    private let dividerView = SeparatorLineView()

    public init() {
        leftEditor = DiffEditorView(side: .left)
        rightEditor = DiffEditorView(side: .right)

        super.init(frame: .zero)

        setupLayout()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        wantsLayer = true

        leftEditor.translatesAutoresizingMaskIntoConstraints = false
        rightEditor.translatesAutoresizingMaskIntoConstraints = false
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftEditor)
        addSubview(dividerView)
        addSubview(rightEditor)

        NSLayoutConstraint.activate([
            leftEditor.topAnchor.constraint(equalTo: topAnchor),
            leftEditor.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftEditor.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftEditor.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor),

            dividerView.topAnchor.constraint(equalTo: topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            rightEditor.topAnchor.constraint(equalTo: topAnchor),
            rightEditor.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            rightEditor.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightEditor.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Both editors have equal width
            leftEditor.widthAnchor.constraint(equalTo: rightEditor.widthAnchor)
        ])
    }
}
