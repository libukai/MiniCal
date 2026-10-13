# 发布 MiniCal

## 源码与本地测试包

修改 VERSION，运行：

```sh
./script/test.sh
./script/build.sh --release
./script/package.sh
```

本地包位于 `dist/packages/*-local.dmg`，可提供给开发者自行构建或测试。它不是已经公证的普通用户发行包。

## Developer ID 正式发行

准备有效的 Apple Developer Program 账号、Keychain 中的 Developer ID Application 证书及相应私钥，以及 `notarytool` Keychain profile。证书和凭据保存在本机 Keychain。

先按 Apple 官方流程创建 profile；下面只使用已保存的 profile 名称：

```sh
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='minical-notary'
./script/notarize.sh
```

脚本执行：ARM release 构建 → Widget 和宿主按顺序签名（Hardened Runtime、时间戳）→ 提交 app ZIP → 确认 Accepted → staple app → 打包、签名 DMG → 提交 DMG → 确认 Accepted → staple DMG → 更新 SHA256。

任何未通过的提交都会终止，不将失败包标成已公证。更改 Bundle ID 需要同时调整构建元数据、应用日志标识和相关发行配置；Widget ID 保持在宿主 ID 前缀下。

发布前需使用**启用默认 Gatekeeper** 的另一台 Mac 验证真实下载、挂载、拖入 Applications、启动、权限请求、菜单栏及 Widget。维护者的本地启动验证不能替代下载用户的信任检查。

准备 GitHub Release 时附上 DMG、SHA256、版本说明和源码标签；上传发布由维护者明确执行。未经公证的包必须保留 `local` 文件名，并在版本说明中明确签名状态及安装限制。

## 签名边界

- ad-hoc 签名只提供本地代码密封，不建立 Developer ID 身份。
- Developer ID 签名不是 Apple 公证；两步都完成才标记“已公证”。
- Widget 必须用 `_NSExtensionMain` 链接入口，主程序使用普通入口。
- 当前本地环境没有 Developer ID 证书，正式签名与公证流程仅已准备，尚未真实执行。

官方参考：[Developer ID](https://developer.apple.com/developer-id/) · [公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
