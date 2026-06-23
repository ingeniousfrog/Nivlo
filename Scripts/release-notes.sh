#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.0.0}"

cat <<EOF
## English

### Nivlo ${VERSION}

Early-access macOS build of Nivlo, a local-first visual asset workbench for indexing, browsing, editing, and exporting images and videos from folders you explicitly authorize.

**Highlights**
- Local indexing with security-scoped folder access
- Search, smart views, duplicate and similarity detection
- Image and video editors (beta)
- Batch export and derivative lineage tracking

**Install**
1. Download \`Nivlo.dmg\`.
2. Drag **Nivlo** into **Applications**.

**Unsigned build notice**

This release is not Apple code-signed or notarized. macOS may block the app on first launch with a message such as *"Nivlo cannot be opened because the developer cannot be verified."*

You can fix that in either of these ways:

- Right-click **Nivlo** in Applications and choose **Open**, then confirm once in the dialog.
- Or remove the download quarantine flag in Terminal:

\`\`\`bash
xattr -cr /Applications/Nivlo.app
\`\`\`

After that, launch Nivlo normally. Your originals are never modified; only authorized folders are indexed.

---

## 简体中文

### Nivlo ${VERSION}

Nivlo 的 macOS 早期测试版：本地优先的视觉素材工作台，可对你明确授权的文件夹建立索引，并进行浏览、编辑与导出。

**主要能力**
- 基于安全范围授权的本地索引
- 搜索、智能视图、重复项与相似图检测
- 图像与视频编辑器（Beta）
- 批量导出与衍生文件谱系追踪

**安装**
1. 下载 \`Nivlo.dmg\`。
2. 将 **Nivlo** 拖入 **Applications**。

**未签名构建说明**

当前发布包尚未进行 Apple 代码签名与公证。首次打开时，macOS 可能会提示 *「无法打开 Nivlo，因为无法验证开发者」* 或类似信息。

可按以下任一方式处理：

- 在应用程序文件夹中 **右键 Nivlo → 打开**，并在弹窗中确认一次。
- 或在终端中清除下载隔离标记：

\`\`\`bash
xattr -cr /Applications/Nivlo.app
\`\`\`

之后即可正常启动。Nivlo 不会修改你的原始文件，只会索引你主动授权的文件夹。
EOF
