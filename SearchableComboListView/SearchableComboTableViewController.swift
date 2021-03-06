//
//  SearchableComboTableViewController.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import AppKit

protocol SearchableComboTableViewControllerDelegate: NSObjectProtocol {
    func searchableComboTableViewController(_ tableViewController: SearchableComboTableViewController,
                                            didSelectItem item: SearchableComboViewItem?)
    func searchableComboTableViewControllerGroups(_ tableViewController: SearchableComboTableViewController) -> [SearchableComboViewGroup]
}

class SearchableComboTableViewController: NSViewController {
    weak var delegate: SearchableComboTableViewControllerDelegate?
    private struct Query {
        let queryTokens: [String]
        init(_ query: String) {
            queryTokens = query.tokens
        }

        func matchesDocumentTokens(_ documentTokens: [String]) -> Bool {
            if queryTokens.isEmpty || documentTokens.isEmpty {
                return true
            }
            for q in queryTokens {
                if documentTokens.allSatisfy({ !$0.hasPrefix(q) }) {
                    return false
                }
            }
            return true
        }
    }

    private enum Row {
        case group(group: SearchableComboViewGroup, index: Int)
        case item(item: SearchableComboViewItem, index: Int)
        var tag: Int? {
            switch self {
            case .group(_):
                return nil
            case .item(item: let item, index: _):
                return item.tag
            }
        }
        func matchesQuery(_ query: Query) -> Bool {
            switch self {
            case .item(item: let item, index: _):
                if let group = item.group, query.matchesDocumentTokens(group.labelTokens) {
                    return true
                }
                return query.matchesDocumentTokens(item.labelTokens)
            case .group(group: let group, index: _):
                if query.matchesDocumentTokens(group.labelTokens) {
                    return true
                }
                return group.items.first(where: { query.matchesDocumentTokens($0.labelTokens) }) != nil
            }
        }
    }

    private var unfilteredRows: [Row] = [] {
        didSet {
            updateFilteredRows()
        }
    }
    private var filteredRows: [Row] = []
    private let checkmarkColumnIdentifier = NSUserInterfaceItemIdentifier("searchableComboViewCheckmark")
    private let labelColumnIdentifier = NSUserInterfaceItemIdentifier("searchableComboViewLabel")
    private let tableView: SearchableComboTableView
    private var dirty = true
    private var internalFilter: String = ""
    private var itemRowHeight: CGFloat!
    private var groupRowHeight: CGFloat!
    private let groupLabelFontSize = NSFont.systemFontSize
    private var previouslySelectedTag: Int? = nil
    private let groupMargin = CGFloat(4)

    var selectedTag: Int? = nil {
        willSet {
            previouslySelectedTag = selectedTag
        }
        didSet {
            var rows = IndexSet()
            if let tag = selectedTag, let rowIndex = rowIndex(withTag: tag) {
                rows.insert(rowIndex)
            }
            if let tag = previouslySelectedTag, let rowIndex = rowIndex(withTag: tag) {
                rows.insert(rowIndex)
            }
            tableView.beginUpdates()
            tableView.reloadData(forRowIndexes: rows,
                                 columnIndexes: IndexSet(integer: 0))
            tableView.endUpdates()
        }
    }

    var filter: String {
        get {
            return internalFilter
        }
        set {
            if newValue != internalFilter {
                dirty = true
            }
            internalFilter = newValue
            updateFilteredRows()
        }
    }

    // MARK:- Initializers

    init(tableView: SearchableComboTableView, groups: [SearchableComboViewGroup]) {
        self.tableView = tableView
        var temp: [Row] = []
        var i = 0
        for group in groups {
            temp.append(.group(group: group, index: i))
            i += 1
            for item in group.items {
                temp.append(.item(item: item, index: i))
                i += 1
            }
        }
        unfilteredRows = temp

        super.init(nibName: nil, bundle: nil)

        updateFilteredRows()
        tableView.intercellSpacing = NSSize(width: 0, height: tableView.intercellSpacing.height)
        tableView.backgroundColor = NSColor.clear
        tableView.floatsGroupRows = true
        let scrollView = tableView.enclosingScrollView!
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                               object: scrollView,
                                               queue: nil) { [weak self] (notification) in
                                                self?.layOutTableView()
        }
        layOutTableView()

        itemRowHeight = newItemLabelCell("X").fittingSize.height + 2
        groupRowHeight = newGroupLabelTextField("X").fittingSize.height + groupMargin * 2

        tableView.delegate = self
        tableView.dataSource = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MAKR:- Helpers

    private func rowIndex(withTag tag: Int) -> Int? {
        for (i, row) in filteredRows.enumerated() {
            if row.tag == tag {
                return i
            }
        }
        return nil
    }

    private func updateFilteredRows() {
        let query = Query(internalFilter)
        filteredRows = unfilteredRows.filter { $0.matchesQuery(query) }
        tableView.reloadData()
    }

    private func itemWithTag(_ tag: Int?) -> SearchableComboViewItem? {
        for row in filteredRows {
            switch row {
            case .group(_):
                break
            case .item(item: let item, index: _):
                if item.tag == tag {
                    return item
                }
            }
        }
        return nil
    }

    // MARK:- Layout

    private func desiredTableViewFrame() -> CGRect {
        guard let scrollView = tableView.enclosingScrollView else {
            return tableView.frame
        }
        var frame = tableView.frame
        frame.size.width = scrollView.frame.size.width
        return frame
    }

    private func layOutTableView() {
        let frame = desiredTableViewFrame()
        tableView.frame = frame
        let checkmarkWidth = CGFloat(16)
        let desiredWidths = [
            checkmarkColumnIdentifier: checkmarkWidth,
            labelColumnIdentifier: frame.size.width - checkmarkWidth
        ]
        for (identifier, width) in desiredWidths {
            if let column = tableView.tableColumn(withIdentifier: identifier) {
                if identifier == checkmarkColumnIdentifier {
                    column.minWidth = width
                    column.maxWidth = width
                }
                column.width = width
            }
        }
    }

    @objc(viewDidLayout)
    public override func viewDidLayout() {
        layOutTableView()
        super.viewDidLayout()
    }

    // MARK:- API

    func select(index: Int?) {
        guard let index = index else {
            delegate?.searchableComboTableViewController(self, didSelectItem: nil)
            return
        }

        switch filteredRows[index] {
        case .group(_):
            return
        case .item(item: let item, _):
            delegate?.searchableComboTableViewController(self, didSelectItem: item)
        }
    }

    // MARK:- Cell Creation

    private func newItemLabelCell(_ value: String) -> NSTextField {
        let identifier = NSUserInterfaceItemIdentifier("SearchableComboViewItemLabelCell")
        if let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textField.stringValue = value
            return textField
        }
        let textField: NSTextField = NSTextField()
        textField.textColor = NSColor.labelColor
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.usesSingleLineMode = true
        textField.identifier = identifier
        textField.stringValue = value
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    private func newGroupLabelTextField(_ value: String) -> NSTextField {
        let identifier = NSUserInterfaceItemIdentifier("SearchableComboViewGroupLabelCell")
        let font = NSFont.systemFont(ofSize: groupLabelFontSize)
        if let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField.font = font
            textField.stringValue = value
            return textField
        }
        let textField: NSTextField = NSTextField()
        textField.textColor = NSColor.labelColor
        textField.font = font
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.usesSingleLineMode = true
        textField.identifier = identifier
        textField.stringValue = value
        textField.lineBreakMode = .byTruncatingTail
        textField.autoresizingMask = []
        textField.sizeToFit()

        return textField;
    }

    private func newGroupLabelCell(_ value: String) -> NSView {
        let textField = newGroupLabelTextField(value)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: textField.bounds.size.width, height: textField.bounds.size.height))
        container.autoresizesSubviews = true
        // Add one point because text rides low in its bounding box.
        textField.frame = NSRect(x: 0, y: groupMargin + 1, width: textField.bounds.size.width, height: textField.bounds.size.height)
        container.addSubview(textField)
        return container
    }

    private func newCheckMarkCell() -> NSTextField {
        let identifier = NSUserInterfaceItemIdentifier("SearchableComboViewCheckMarkTableViewCellIdentifier")
        if let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField.stringValue = "???"
            textField.alignment = .right
            return textField
        }
        let textField: NSTextField = NSTextField()
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.usesSingleLineMode = true
        textField.identifier = identifier
        textField.stringValue = "???"
        return textField
    }
}

extension SearchableComboTableViewController: NSTableViewDataSource {
    @objc(numberOfRowsInTableView:)
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredRows.count
    }

    @objc(tableView:viewForTableColumn:row:)
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier == checkmarkColumnIdentifier {
            let cell = newCheckMarkCell()
            let hideCheck = selectedTag == nil || filteredRows[row].tag != selectedTag
            cell.isHidden = hideCheck
            return cell
        }

        // Label
        switch filteredRows[row] {
        case .group(group: let group, index: _):
            return newGroupLabelCell(group.label)
        case .item(item: let item, index: _):
            return newItemLabelCell(item.label)
        }
    }

    @objc(tableView:heightOfRow:)
    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch filteredRows[row] {
        case .group(_):
            return groupRowHeight
        case .item(_):
            return itemRowHeight
        }
    }

    @objc(tableView:shouldSelectRow:)
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch filteredRows[row] {
        case .group(group: _, index: _):
            return false
        case .item(item: _, index: _):
            return true
        }
    }

    public func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        if self.tableView(tableView, isGroupRow: row) {
            rowView.backgroundColor = NSColor.underPageBackgroundColor
        }
    }

    public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        switch filteredRows[row] {
        case .group(group: _, index: _):
            return true
        case .item(item: _, index: _):
            return false
        }
    }
}

extension SearchableComboTableViewController: NSTableViewDelegate {
    @objc(tableViewSelectionDidChange:)
    public func tableViewSelectionDidChange(_ notification: Notification) {
        if tableView.handlingKeyDown {
            return
        }
        let row = tableView.selectedRow
        guard row >= 0 else {
            selectedTag = -1
            return
        }
        selectedTag = filteredRows[row].tag
        delegate?.searchableComboTableViewController(self, didSelectItem: itemWithTag(selectedTag))
    }
}


