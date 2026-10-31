import AppKit

/// Modern, sleek pill-styled button for macOS toolbars and control bars.
public final class ModernPillButton: NSButton {
    public var isToggle: Bool = false
    public var accentTintWhenActive: Bool = false
    private var isHovered: Bool = false
    private var isPressed: Bool = false
    private var trackingArea: NSTrackingArea?

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

    private func setup() {
        wantsLayer = true
        isBordered = false
        setButtonType(isToggle ? .pushOnPushOff : .momentaryPushIn)
        font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        layer?.cornerRadius = 6.0
        layer?.borderWidth = 1.0
        updateColors()
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
        updateColors()
        super.mouseDown(with: event)
        isPressed = false
        updateColors()
    }

    public override var isEnabled: Bool {
        didSet {
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
        updateColors()
    }

    /// Borderless buttons hug their title; give the pill breathing room.
    public override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 20, height: size.height)
    }

    private func cg(_ color: NSColor) -> CGColor {
        return DiffTheme.cgColor(color, for: self)
    }

    public func updateColors() {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let isActive = (state == .on && isToggle)

        if isActive && accentTintWhenActive {
            layer?.backgroundColor = cg(DiffTheme.hoverArrowColor.withAlphaComponent(isDark ? 0.25 : 0.16))
            layer?.borderColor = cg(DiffTheme.hoverArrowColor.withAlphaComponent(isDark ? 0.65 : 0.45))
            contentTintColor = isDark ? NSColor.white : DiffTheme.hoverArrowColor
            alphaValue = 1.0
        } else if !isEnabled {
            layer?.backgroundColor = cg(NSColor.clear)
            layer?.borderColor = cg(NSColor.separatorColor.withAlphaComponent(0.12))
            contentTintColor = NSColor.disabledControlTextColor
            alphaValue = 0.40
        } else if isPressed {
            alphaValue = 1.0
            layer?.backgroundColor = cg(NSColor.labelColor.withAlphaComponent(isDark ? 0.20 : 0.14))
            layer?.borderColor = cg(NSColor.separatorColor.withAlphaComponent(0.50))
            contentTintColor = NSColor.labelColor
        } else if isHovered {
            alphaValue = 1.0
            layer?.backgroundColor = cg(NSColor.labelColor.withAlphaComponent(isDark ? 0.14 : 0.08))
            layer?.borderColor = cg(NSColor.separatorColor.withAlphaComponent(0.40))
            contentTintColor = NSColor.labelColor
        } else {
            alphaValue = 1.0
            layer?.backgroundColor = cg(NSColor.labelColor.withAlphaComponent(isDark ? 0.06 : 0.035))
            layer?.borderColor = cg(NSColor.separatorColor.withAlphaComponent(isDark ? 0.22 : 0.18))
            contentTintColor = NSColor.secondaryLabelColor
        }
    }
}

private final class StatChipLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width + 10, 24), height: 18)
    }
}

/// Exquisite, modern status capsule showing diff summary, addition & deletion chips.
public final class ModernStatusCapsuleView: NSView {
    private let dotLabel = NSTextField(labelWithString: "○")
    private let titleLabel = NSTextField(labelWithString: "Waiting for input")
    private let additionChip = StatChipLabel(labelWithString: "+0")
    private let deletionChip = StatChipLabel(labelWithString: "-0")
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

        // Addition chip (+N)
        additionChip.wantsLayer = true
        additionChip.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        additionChip.textColor = DiffTheme.additionIndicatorColor
        additionChip.layer?.cornerRadius = 5.0
        additionChip.alignment = .center
        additionChip.isHidden = true

        // Deletion chip (-N)
        deletionChip.wantsLayer = true
        deletionChip.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        deletionChip.textColor = DiffTheme.deletionIndicatorColor
        deletionChip.layer?.cornerRadius = 5.0
        deletionChip.alignment = .center
        deletionChip.isHidden = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6.0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(dotLabel)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(additionChip)
        stackView.addArrangedSubview(deletionChip)

        addSubview(stackView)
        updateLayerColors()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
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
        additionChip.layer?.backgroundColor = DiffTheme.cgColor(DiffTheme.additionIndicatorColor.withAlphaComponent(0.18), for: self)
        deletionChip.layer?.backgroundColor = DiffTheme.cgColor(DiffTheme.deletionIndicatorColor.withAlphaComponent(0.18), for: self)
    }

    public func setWaitingForInput() {
        dotLabel.stringValue = "○"
        dotLabel.textColor = NSColor.tertiaryLabelColor
        titleLabel.stringValue = "Ready for input"
        titleLabel.textColor = NSColor.secondaryLabelColor
        additionChip.isHidden = true
        deletionChip.isHidden = true
        setAccessibilityValue("Ready for input")
    }

    public func setIdentical() {
        dotLabel.stringValue = "✔"
        dotLabel.textColor = DiffTheme.additionIndicatorColor
        titleLabel.stringValue = "Files identical"
        titleLabel.textColor = DiffTheme.additionIndicatorColor
        additionChip.isHidden = true
        deletionChip.isHidden = true
        setAccessibilityValue("Files identical")
    }

    public func setDiff(hunksCount: Int, additions: Int, deletions: Int) {
        dotLabel.stringValue = "●"
        dotLabel.textColor = DiffTheme.hoverArrowColor
        let hunkWord = (hunksCount == 1) ? "change" : "changes"
        titleLabel.stringValue = "\(hunksCount) \(hunkWord)"
        titleLabel.textColor = NSColor.labelColor

        if additions > 0 {
            additionChip.stringValue = "+\(additions)"
            additionChip.isHidden = false
        } else {
            additionChip.isHidden = true
        }

        if deletions > 0 {
            deletionChip.stringValue = "-\(deletions)"
            deletionChip.isHidden = false
        } else {
            deletionChip.isHidden = true
        }
        setAccessibilityValue("\(hunksCount) \(hunkWord), \(additions) lines added, \(deletions) lines removed")
    }
}

/// 1px hairline that follows light/dark appearance changes (layer colors set once would not).
public final class SeparatorLineView: NSView {
    public override func draw(_ dirtyRect: NSRect) {
        DiffTheme.gutterBorder.setFill()
        dirtyRect.fill()
    }
}
