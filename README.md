# 梗斗竞技场

奶蛙、牛来、袋鼠、豆包的 Godot 4.6.3 2D 横版格斗游戏。支持本地双人、玩家对人机和训练模式。

**[浏览器直接游玩](https://xingyuliu586-tech.github.io/gengdou-arena/)**

建议在电脑上使用键盘，首次载入需要下载游戏资源。点击“开始游戏”，进入后点击画面启用声音与键盘。双人模式需要两名玩家共用同一台电脑。

## 操作

- 1P：A / D 移动，K 跳跃，S 防御，J 普攻，U 技能，I 大招，L 冲刺。
- 2P：方向键移动/防御，1 普攻，2 跳跃，3 冲刺，4 技能，5 大招；主键盘数字和小键盘均可。
- J / Enter 确认菜单；Esc 暂停。大招需要满能量。

## 修改源工程

使用 **Godot 4.6.3 标准版**导入 `project.godot`，等资源导入完成后按 F5 运行。没有 .NET 和第三方插件依赖。

- `scripts/main.gd`：主要战斗逻辑、输入、人机、界面和绘制。
- `scripts/ultimate_presentation.gd`：大招切入和字幕。
- `scenes/格斗主场景.tscn`：主场景。
- `assets/`：角色、背景、特效、声音和字体。
- `reference/`：角色参考图；`docs/`：设计与演出交接资料。
- `web/shell.html`：网页加载页、操作说明和全屏按钮。

更详细的修改说明见《先看这里_工程修改说明.md》和《试玩说明.md》。当前动画以关键姿势补间为主，完整逐帧动画可继续完善。

## 网页构建与部署

项目使用兼容渲染器和不启用线程的 Web 导出。安装对应版本的 Godot Web 导出模板后，可以在编辑器选择 Web 预设导出；也可以运行：

```sh
godot --headless --editor --path . --import
mkdir -p builds/web
godot --headless --path . --export-release Web builds/web/index.html
python -m http.server 8000 --directory builds/web
```

然后访问 `http://localhost:8000`。网页不能通过直接双击 HTML 的方式运行。

推送到 `main` 会触发 `.github/workflows/pages.yml`，自动导出游戏并发布到 GitHub Pages。可在仓库 Actions 页查看构建日志。

素材和用户提供音轨的来源说明见 `docs/`。本仓库没有为参考角色、音乐或其他素材授予额外使用许可。
