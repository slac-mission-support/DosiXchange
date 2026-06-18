//
//  PopupAlertController.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/18/26.
//

import UIKit

//A button in a PopupAlertController, mirroring UIAlertAction's title/style/handler.
struct PopupAction {
    enum Style {
        case normal
        case cancel
        case destructive
    }

    let title: String
    let style: Style
    let handler: (() -> Void)?

    init(title: String, style: Style = .normal, handler: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }
}

//A centered, Auto-Layout alert that replaces the UIAlertControllers which floated
//an image or switch at hardcoded frames (mis-rendered as the system alert metrics
//changed). Title/message/actions keep UIAlertController semantics.
final class PopupAlertController: UIViewController {

    //A labeled on/off row shown above the buttons (e.g. the RGD toggle).
    //onChange fires on every flip; the popup stays open since only buttons dismiss.
    private struct SwitchSpec {
        let title: String
        let isOn: Bool
        let color: UIColor?
        let onChange: (Bool) -> Void
    }

    //A single-line text input row (e.g. the deploy location field). onChange fires
    //on every edit so callers track the value without reaching back into the popup.
    private struct TextFieldSpec {
        let text: String?
        let placeholder: String?
        let onChange: (String) -> Void
    }

    //Content rows are rendered in the order they're added, so sections, switches,
    //and a text field can interleave (e.g. the map legend's Active/Inactive groups).
    private enum ContentItem {
        case section(String)
        case toggle(SwitchSpec)
        case textField(TextFieldSpec)
    }

    private let popupTitle: String?
    private let popupMessage: String?
    private var image: UIImage?
    private var actions: [PopupAction] = []
    private var contentItems: [ContentItem] = []
    private var cardColor: UIColor = .systemBackground

    private let card = UIView()
    private let contentStack = UIStackView()
    private var cardCenterY: NSLayoutConstraint?

    init(title: String?, message: String?) {
        self.popupTitle = title
        self.popupMessage = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("PopupAlertController is created in code, not from a coder")
    }

    //Sets the picture shown between the message and the buttons. No image = no row.
    func setImage(_ image: UIImage?) {
        self.image = image
    }

    //Tints the card (e.g. the yellow warning dialog). nil keeps the default
    //system background. This replaces reaching into UIAlertController's private
    //subview tree to recolor it, which broke as that tree changed across iOS.
    func setBackgroundColor(_ color: UIColor?) {
        if let color { cardColor = color }
    }

    func addAction(_ action: PopupAction) {
        actions.append(action)
    }

    //Adds a labeled switch row between the content and the buttons. Replaces the
    //old pattern of floating a UISwitch onto the alert at a hardcoded frame. color
    //sets the on-tint (e.g. the map legend's red/green/orange/... swatches).
    func addSwitch(title: String, isOn: Bool, color: UIColor? = nil, onChange: @escaping (Bool) -> Void) {
        contentItems.append(.toggle(SwitchSpec(title: title, isOn: isOn, color: color, onChange: onChange)))
    }

    //Adds a bold, left-aligned section header (e.g. the map legend's "Active").
    func addSection(title: String) {
        contentItems.append(.section(title))
    }

    //Adds a single-line text field row. onChange fires on every edit.
    func addTextField(text: String?, placeholder: String?, onChange: @escaping (String) -> Void) {
        contentItems.append(.textField(TextFieldSpec(text: text, placeholder: placeholder, onChange: onChange)))
    }

    private var hasTextField: Bool {
        contentItems.contains { if case .textField = $0 { return true } else { return false } }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Pin to light like the rest of the app so the card stays a light background
        // in any mode — consistent across iOS, and transparent-background images
        // (QRCodeImage.png is a black QR on alpha) stay visible instead of vanishing.
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        buildCard()
        if hasTextField { observeKeyboard() }
    }

    private func buildCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = cardColor
        card.layer.cornerRadius = 13.5
        card.clipsToBounds = true
        view.addSubview(card)

        let margin = view.safeAreaLayoutGuide
        let centerY = card.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        cardCenterY = centerY
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerY,
            card.widthAnchor.constraint(equalToConstant: 270),
            card.topAnchor.constraint(greaterThanOrEqualTo: margin.topAnchor, constant: 20),
            card.bottomAnchor.constraint(lessThanOrEqualTo: margin.bottomAnchor, constant: -20)
        ])

        //The card stacks a scrollable content area over the button area, so long
        //messages or a tall image scroll instead of pushing the buttons off screen.
        let outerStack = UIStackView()
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.axis = .vertical
        card.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: card.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        outerStack.addArrangedSubview(buildContentScrollView())
        outerStack.addArrangedSubview(buildButtons())
    }

    private func buildContentScrollView() -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = .init(top: 19, leading: 16, bottom: 19, trailing: 16)

        if let popupTitle, !popupTitle.isEmpty {
            contentStack.addArrangedSubview(makeLabel(text: popupTitle,
                                                      font: .boldSystemFont(ofSize: 17)))
        }
        if let popupMessage, !popupMessage.isEmpty {
            contentStack.addArrangedSubview(makeLabel(text: popupMessage,
                                                      font: .systemFont(ofSize: 13)))
        }
        if let image {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.heightAnchor.constraint(equalToConstant: 90).isActive = true
            contentStack.addArrangedSubview(imageView)
        }
        for item in contentItems {
            switch item {
            case .section(let title):
                contentStack.addArrangedSubview(makeSectionHeader(title))
            case .toggle(let spec):
                contentStack.addArrangedSubview(makeSwitchRow(for: spec))
            case .textField(let spec):
                contentStack.addArrangedSubview(makeTextFieldRow(for: spec))
            }
        }

        scrollView.addSubview(contentStack)
        let frame = scrollView.frameLayoutGuide
        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: content.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: frame.widthAnchor)
        ])

        // Without this the scroll view has no intrinsic height in the outer stack,
        // collapses to 0pt, and clips the content. Hugging the content sizes the card
        // to fit; below-required priority lets the max-height cap win and scroll.
        let visibleHeight = frame.heightAnchor.constraint(equalTo: contentStack.heightAnchor)
        visibleHeight.priority = .defaultHigh
        visibleHeight.isActive = true

        return scrollView
    }

    //Buttons stack vertically, each 44pt tall with a hairline above and between
    //them. A horizontal two-button row can be added later if a popup needs it.
    private func buildButtons() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .fill
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addArrangedSubview(makeSeparator(vertical: false))
        for (index, action) in actions.enumerated() {
            if index > 0 {
                container.addArrangedSubview(makeSeparator(vertical: false))
            }
            container.addArrangedSubview(makeButton(for: action, index: index))
        }
        return container
    }

    //A horizontal row: left-aligned title that expands, switch pinned to the right.
    private func makeSwitchRow(for spec: SwitchSpec) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8

        let label = UILabel()
        label.text = spec.title
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toggle = UISwitch()
        toggle.isOn = spec.isOn
        toggle.onTintColor = spec.color
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        // Read the switch off the action's sender rather than capturing `toggle`,
        // which would retain-cycle the switch with its own action.
        toggle.addAction(UIAction { action in
            if let toggle = action.sender as? UISwitch { spec.onChange(toggle.isOn) }
        }, for: .valueChanged)

        row.addArrangedSubview(label)
        row.addArrangedSubview(toggle)
        return row
    }

    private func makeSectionHeader(_ title: String) -> UILabel {
        let header = UILabel()
        header.text = title
        header.font = .boldSystemFont(ofSize: 17)
        header.numberOfLines = 0
        return header
    }

    private func makeTextFieldRow(for spec: TextFieldSpec) -> UITextField {
        let field = UITextField()
        field.text = spec.text
        field.placeholder = spec.placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.heightAnchor.constraint(equalToConstant: 36).isActive = true
        field.addAction(UIAction { action in
            if let field = action.sender as? UITextField { spec.onChange(field.text ?? "") }
        }, for: .editingChanged)
        return field
    }

    // The card is vertically centred, so the keyboard would cover the buttons of a
    // text-field popup (e.g. deploy). Shift the card up by half the keyboard height
    // while it's shown so it stays centred in the visible area.
    private func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        cardCenterY?.constant = -frame.height / 2
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide() {
        cardCenterY?.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func makeLabel(text: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makeButton(for action: PopupAction, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(action.title, for: .normal)
        button.titleLabel?.font = action.style == .cancel
            ? .boldSystemFont(ofSize: 17)
            : .systemFont(ofSize: 17)
        button.setTitleColor(action.style == .destructive ? .systemRed : view.tintColor, for: .normal)
        button.tag = index
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func makeSeparator(vertical: Bool) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        let thickness = line.dimensionAnchor(vertical: vertical)
        thickness.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    @objc private func actionTapped(_ sender: UIButton) {
        let action = actions[sender.tag]
        dismiss(animated: true) {
            action.handler?()
        }
    }
}

private extension UIView {
    //Returns the width anchor for a vertical separator, height anchor otherwise.
    func dimensionAnchor(vertical: Bool) -> NSLayoutDimension {
        vertical ? widthAnchor : heightAnchor
    }
}
