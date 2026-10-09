import UIKit

extension UIViewController {
    /// 统一的 NodeImage 取 Key 入口。
    ///
    /// 优先自动获取：打开图床站点，已登录时点顶部 API 入口就能读到 Key，
    /// 未登录时同一个页面里就能走 NodeSeek 授权。手动粘贴作为该页左上角的
    /// 兜底按钮保留，不再让每个上传入口各自弹一个粘贴框。
    ///
    /// 不直接请求 `/api/user/api-key`：未登录时该接口返回 404 而不是 401，
    /// 拿不到真实响应结构，字段名只能靠猜；DOM 抓取那条路径是实测可用的。
    @MainActor
    func presentNodeImageAuthorization(then onComplete: @escaping @MainActor (String) -> Void) {
        let authorizationViewController = NodeImageAuthViewController { [weak self] apiKey in
            guard let self else { return }
            let normalized = NodeImageAPIKeyNormalizer.normalized(apiKey)
            guard normalized.isEmpty == false else { return }
            self.dismiss(animated: true) {
                onComplete(normalized)
            }
        }
        present(UINavigationController(rootViewController: authorizationViewController), animated: true)
    }
}
