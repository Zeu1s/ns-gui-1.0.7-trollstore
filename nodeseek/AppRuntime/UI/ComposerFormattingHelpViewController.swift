import UIKit

/// 回复框工具栏里"格式说明"那一项的内容。
///
/// 只列这个 App 真的会插入的东西，以及提交时到底发出去什么 ——
/// 不照抄第三方 Markdown 文档，因为本站编辑器收到的是
/// "HTML 标签 + Markdown 混排的纯文本"，由站点自己归一化。
final class ComposerFormattingHelpViewController: UITableViewController {
    private struct Row {
        let title: String
        let detail: String
    }

    private struct Section {
        let header: String
        let rows: [Row]
    }

    private let sections: [Section] = [
        Section(header: "工具栏按钮", rows: [
            Row(title: "粗体 / 斜体 / 下划线 / 删除线",
                detail: "选中文字后点一下即套上，再点取消。提交时写成 <strong> <em> <u> <s> 标签。"),
            Row(title: "链接",
                detail: "填显示文字和地址，插入的是 <a href=\"地址\">文字</a>：帖子只显示文字，点文字跳转。文字留空则显示地址本身。"),
            Row(title: "最右侧 Aa（更多格式）",
                detail: "标题、无序列表、有序列表、引用、行内代码、代码块、插入表格、分隔线、清除格式。")
        ]),
        Section(header: "更多格式里插入的是 Markdown 原文", rows: [
            Row(title: "标题", detail: "行首加 ## ，即二级标题"),
            Row(title: "无序列表 / 有序列表", detail: "行首加 -  或 1. "),
            Row(title: "引用", detail: "行首加 > "),
            Row(title: "行内代码 / 代码块", detail: "单反引号包裹，或三个反引号独占一段"),
            Row(title: "分隔线", detail: "单独一行写 ---")
        ]),
        Section(header: "几点容易踩的坑", rows: [
            Row(title: "两种写法可以同时用",
                detail: "提交的是纯文本，站点编辑器会自己把 HTML 标签和 Markdown 都渲染出来。"),
            Row(title: "图片可以直接贴地址",
                detail: "粘贴一个图片链接，站点会渲染成图片，不必走上传。"),
            Row(title: "格式以预览为准",
                detail: "发出去长什么样，站点自己的预览最准；这个页面只说明这里按下去会插入什么。")
        ])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "支持的格式"
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HelpRow")
        tableView.separatorStyle = .singleLine
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeTapped)
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HelpRow", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = row.title
        configuration.secondaryText = row.detail
        configuration.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = configuration
        cell.backgroundColor = .systemBackground
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}
