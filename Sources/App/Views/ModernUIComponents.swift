import AppKit

/// Borderless, icon-only toolbar button.
///
/// At rest it is just a quiet SF Symbol glyph — no border, no fill. Hovering fades in a
/// soft rounded plate behind it; pressing deepens the plate. Toggles that are on show the
/// glyph in the accent color on a faint accent plate.
public final class ModernPillButton: NSButton {
    public var isToggle: Bool = false
    public var accentTintWhenActive: Bool = false
    private var isHovered: Bool = false
    private var isPressed: Bool = false
    private var trackingArea: NSTrackingArea?

    public static let symbolPointSize: CGFloat = 15.0
    public static let size = NSSize(width: 32, height: 28)

    /// Icon button backed by an SF Symbol.
    public init(symbol: String, accessibilityLabel: String, isToggle: Bool = false, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.isToggle = isToggle
        self.target = target
        self.action = action
        self.title = ""
        setup()
        setSymbol(symbol, accessibilityLabel: accessibilityLabel)
        setAccessibilityLabel(accessibilityLabel)
    }

    public init(title: String, isToggle: Bool = false, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.isToggle = isToggle
        self.target = target
        self.action = action
        self.title = title
        setup()
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    public func setSymbol(_ name: String, accessibilityLabel: String? = nil) {
        let config = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        self.image = image
        imagePosition = .imageOnly
        imageScaling = .scaleNone
    }

    private func setup() {
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(isToggle ? .pushOnPushOff : .momentaryPushIn)
        font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        layer?.cornerRadius = 7.0
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.0
        updateColors(animated: false)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateColors()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateColors()
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateColors(animated: false)
        super.mouseDown(with: event)
        isPressed = false
        updateColors()
    }

    public override var isEnabled: Bool {
        didSet {
            if !isEnabled { isHovered = false }
            updateColors()
        }
    }

    public override var state: NSControl.StateValue {
        didSet {
            updateColors()
        }
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors(animated: false)
    }

    public override var intrinsicContentSize: NSSize {
        if image != nil && title.isEmpty { return Self.size }
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 20, height: max(size.height, Self.size.height))
    }

    private func cg(_ color: NSColor) -> CGColor {
        return DiffTheme.cgColor(color, for: self)
    }

    public func updateColors(animated: Bool = true) {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let isActive = (state == .on && isToggle)

        let fill: NSColor
        let tint: NSColor
        if !isEnabled {
            fill = .clear
            tint = NSColor.labelColor.withAlphaComponent(isDark ? 0.22 : 0.20)
        } else if isActive && accentTintWhenActive {
            // "On" is signalled by a brighter glyph alone; only hover/press add the neutral plate.
            fill = isPressed
                ? NSColor.labelColor.withAlphaComponent(isDark ? 0.16 : 0.11)
                : (isHovered ? NSColor.labelColor.withAlphaComponent(isDark ? 0.09 : 0.06) : .clear)
            // Full-strength label color: white in Dark Mode, near-black in Light Mode.
            tint = NSColor.labelColor
        } else if isPressed {
            fill = NSColor.labelColor.withAlphaComponent(isDark ? 0.16 : 0.11)
            tint = NSColor.labelColor
        } else if isHovered {
            fill = NSColor.labelColor.withAlphaComponent(isDark ? 0.09 : 0.06)
            tint = NSColor.labelColor
        } else {
            fill = .clear
            tint = NSColor.secondaryLabelColor
        }

        contentTintColor = tint
        alphaValue = 1.0

        let newColor = cg(fill)
        if animated, let layer = layer, window != nil {
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            anim.toValue = newColor
            anim.duration = 0.14
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "backgroundColor")
        }
        layer?.backgroundColor = newColor
    }
}

/// Exquisite, modern status capsule showing diff summary.
public final class ModernStatusCapsuleView: NSView {
    private let dotLabel = NSTextField(labelWithString: "○")
    private let titleLabel = NSTextField(labelWithString: "Waiting for input")
    private let stackView = NSStackView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 14.0
        layer?.borderWidth = 1.0
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)

        dotLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        dotLabel.textColor = NSColor.tertiaryLabelColor
        dotLabel.alignment = .center

        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = NSColor.secondaryLabelColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6.0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(dotLabel)
        stackView.addArrangedSubview(titleLabel)

        addSubview(stackView)
        updateLayerColors()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        layer?.backgroundColor = DiffTheme.cgColor(NSColor.labelColor.withAlphaComponent(isDark ? 0.07 : 0.04), for: self)
        layer?.borderColor = DiffTheme.cgColor(NSColor.separatorColor.withAlphaComponent(isDark ? 0.25 : 0.18), for: self)
    }

    public func setWaitingForInput() {
        dotLabel.stringValue = "○"
        dotLabel.textColor = NSColor.tertiaryLabelColor
        titleLabel.stringValue = "Ready for input"
        titleLabel.textColor = NSColor.secondaryLabelColor
        setAccessibilityValue("Ready for input")
    }

    public func setIdentical() {
        dotLabel.stringValue = "✔"
        dotLabel.textColor = DiffTheme.additionIndicatorColor
        titleLabel.stringValue = "Files identical"
        titleLabel.textColor = DiffTheme.additionIndicatorColor
        setAccessibilityValue("Files identical")
    }

    public func setDiff(hunksCount: Int, additions: Int = 0, deletions: Int = 0) {
        dotLabel.stringValue = "●"
        dotLabel.textColor = DiffTheme.hoverArrowColor
        let hunkWord = (hunksCount == 1) ? "change" : "changes"
        titleLabel.stringValue = "\(hunksCount) \(hunkWord)"
        titleLabel.textColor = NSColor.labelColor
        setAccessibilityValue("\(hunksCount) \(hunkWord)")
    }
}

/// 1px hairline that follows light/dark appearance changes (layer colors set once would not).
public final class SeparatorLineView: NSView {
    public override func draw(_ dirtyRect: NSRect) {
        DiffTheme.gutterBorder.setFill()
        dirtyRect.fill()
    }
}

/// An elegant HUD overlay indicating "Press ⌘Q again to quit".
public final class QuitConfirmationHUDView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.masksToBounds = false

        // Subtle drop shadow for depth floating above the code editors
        let dropShadow = NSShadow()
        dropShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        dropShadow.shadowOffset = NSSize(width: 0, height: -3)
        dropShadow.shadowBlurRadius = 12
        shadow = dropShadow

        visualEffectView.material = .popover
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        let attributedTitle = NSMutableAttributedString(
            string: "Press ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.0, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributedTitle.append(NSAttributedString(
            string: "⌘Q",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        attributedTitle.append(NSAttributedString(
            string: " again to quit",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13.0, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        ))

        titleLabel.attributedStringValue = attributedTitle
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 9),
            titleLabel.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -9),
            titleLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -18),
        ])

        updateBorder()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        visualEffectView.layer?.borderColor = DiffTheme.cgColor(
            NSColor.separatorColor.withAlphaComponent(isDark ? 0.35 : 0.20),
            for: self
        )
    }

    // Transparent to mouse clicks so the HUD never blocks clicks on views underneath
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

