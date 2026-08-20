import AuthenticationServices
import SQLite3

/// iOS 凭据提供者扩展主控制器。
///
/// 用户在「设置 > 密码 > 自动填充 > KeyRing」启用后，系统键盘的
/// 「密码」按钮会唤起本扩展。本实现读取 App Group 共享容器中的
/// KeyRing 数据库副本，以列表形式展示条目供用户点选填充。
///
/// 主 app 需在启动/数据变化时把 KeyRing.db 同步到共享容器
/// （见 ios/CredentialProvider/SETUP_AUTOFILL.md）。
class CredentialProviderViewController: ASCredentialProviderViewController,
    UITableViewDataSource, UITableViewDelegate {

    private struct Entry {
        let id: String
        let title: String
        let username: String
        let password: String
    }

    private var entries: [Entry] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel, target: nil, action: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        title = "KeyRing"
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
        navigationItem.leftBarButtonItem = cancelButton

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(Value1Cell.self, forCellReuseIdentifier: "cell")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)

        entries = CredentialStore().loadEntries().map {
            Entry(id: $0.id, title: $0.title, username: $0.username, password: $0.password)
        }
    }

    @objc private func cancelAction() {
        extensionContext.cancelRequest(
            withError: NSError(domain: "com.example.key_ring", code: 0))
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let e = entries[indexPath.row]
        cell.textLabel?.text = e.title
        cell.detailTextLabel?.text = e.username
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let e = entries[indexPath.row]
        let credential = ASPasswordCredential(
            user: e.username, password: e.password)
        extensionContext.completeRequest(
            withSelectedCredential: credential, completionHandler: nil)
    }

    // MARK: - ASCredentialProviderViewController

    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity,
    ) {
        // 静默填充需要凭据标识同步；当前版本引导用户手动选择。
        extensionContext.cancelRequest(
            withError: NSError(
                domain: "com.example.keyRing.autofill",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "User interaction required"],
            ),
        )
    }

    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
    ) {
        // viewDidLoad 已加载列表，此处无需额外处理。
    }
}

/// 带副标题的 cell 样式（默认样式没有 detailTextLabel）。
private final class Value1Cell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 从 App Group 共享容器只读加载 KeyRing 数据库条目。
struct CredentialStore {
    /// 与主 app 一致的 App Group ID（两个 target 的 entitlements 都要配）。
    static let appGroupId = "group.com.example.key_ring.shared"

    func loadEntries() -> [(id: String, title: String, username: String, password: String)] {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.appGroupId)
        else { return [] }

        let dbPath = container.appendingPathComponent("KeyRing.db").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              db != nil
        else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, title, username, password FROM password_items
        ORDER BY isFavorite DESC, datetime(updatedAt) DESC LIMIT 200
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var result: [(String, String, String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func col(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map {
                    String(cString: $0)
                } ?? ""
            }
            result.append((col(0), col(1), col(2), col(3)))
        }
        return result
    }
}
