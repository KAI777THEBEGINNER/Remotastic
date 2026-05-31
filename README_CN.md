# Siri Remote for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 本项目基于 [Remotastic](https://github.com/laurentschuermans/Remotastic)（作者：Laurent Schuermans）进行二次开发与改进，增加了更多设备支持、界面优化和稳定性增强。

用 Apple TV Siri Remote 控制你的 Mac——一款轻量级菜单栏应用，把你的 Siri Remote 变成触控板和媒体控制器。

## 功能

- **真正的触控体验**：Siri Remote 触摸板流畅移动光标，支持点击、拖拽和双指滚动
- **可自定义按钮映射**：将任意遥控器按钮映射为媒体控制、鼠标操作或键盘快捷键
- **暂停 / 恢复**：一键开关所有映射，工作时避免与妙控板冲突
- **光标与滚动速度**：直接从菜单栏调节触控板灵敏度
- **多显示器支持**：光标可在所有显示器间移动
- **自动重连**：遥控器休眠或蓝牙断开后自动恢复
- **菜单栏集成**：快速访问设置、连接状态和暂停开关

## 支持的设备

已在以下 Apple TV Siri Remote 型号上测试通过：

| 厂商 ID | 产品 ID | 型号 |
|---------|---------|------|
| 0x004C  | 0x0315  | Apple TV Remote (2021 / 第三代) |
| 0x004C  | 0x030E  | Siri Remote (第二代) |
| 0x004C  | 0x030D  | Siri Remote (第二代， alternate) |
| 0x004C  | 0x0269  | Siri Remote (第一代) |
| 0x004C  | 0x0267  | Siri Remote (第一代， alternate) |
| 0x004C  | 0x0266  | Siri Remote (第一代， alternate) |
| 0x004C  | 0x0255  | Apple TV Remote (早期型号) |
| 0x004C  | 0x0221  | Apple TV Remote (早期型号) |

其他型号如果暴露了兼容的 HID 接口，也可能正常工作。

## 安装

**前置条件**：macOS 11.0+、Xcode Command Line Tools、通过蓝牙配对好的 Apple TV Siri Remote。

```bash
git clone https://github.com/KAI777THEBEGINNER/Remotastic.git
cd Remotastic
./build.sh
./create_app_bundle.sh
cp -R Remotastic.app /Applications/
```

然后在「应用程序」文件夹中双击 **Siri Remote for macOS**。

## 必需权限

Siri Remote for macOS 需要两项系统权限才能正常工作：

1. **辅助功能**（系统设置 → 隐私与安全性 → 辅助功能）
   - 用途：光标移动、鼠标点击、模拟键盘快捷键
2. **输入监听**（系统设置 → 隐私与安全性 → 输入监听）
   - 用途：拦截系统媒体键，防止重复触发

当需要某项权限时，应用会自动弹出提示。

## 配对遥控器

1. 在 Siri Remote 上，按住 **Menu + 音量加** 键 5 秒钟
2. 在 Mac 上，打开 **系统设置 → 蓝牙**
3. 在列表中选择你的遥控器，点击 **连接**
4. 打开 Siri Remote for macOS——它会自动出现在菜单栏中

## 使用说明

点击菜单栏中的 **Siri Remote for macOS** 图标可以：

- 查看蓝牙连接状态
- 按应用配置按钮映射
- 切换 **暂停 / 恢复**，临时禁用所有遥控器输入
- 调节 **光标速度** 和 **滚动速度**

### 默认按钮映射

| 遥控器按钮 | 默认动作 | 说明 |
|-----------|---------|------|
| **Menu**  | Escape  | 发送 Escape 键 |
| **Siri**  | Fn      | 发送 Function 键 |
| **播放/暂停**| 播放/暂停 | 系统媒体播放/暂停 |
| **音量 +** | 音量加  | 系统音量增加 |
| **音量 −** | 音量减  | 系统音量减少 |
| **TV**    | 无      | 默认不映射 |
| **Select**| 点击    | 鼠标左键点击（按住可拖拽）|
| **电源**  | 无      | 默认不映射 |

### 触摸板手势

| 手势 | 动作 |
|------|------|
| **单指滑动** | 移动光标 |
| **单指轻点** | 左键点击 |
| **双指滑动** | 滚动 |
| **用力按压** | 左键点击 / 开始拖拽（按住并滑动以拖拽）|

## 故障排除

| 问题 | 解决方法 |
|------|---------|
| 遥控器显示「未连接」 | 检查蓝牙配对状态，按任意遥控器按钮唤醒，然后等待几秒 |
| 光标不移动 | 在系统设置中确认已给 Siri Remote for macOS 开启**辅助功能**权限 |
| 触摸只能横平竖直移动 | 彻底退出 Siri Remote for macOS 再重新打开；确保没有其他实例在后台运行 |
| 按按钮时有系统提示音 | 说明 Siri Remote for macOS 没有独占 HID 访问权；退出并重新打开应用 |
| 按钮可用但触摸无效 | 确保遥控器已完全配对（在蓝牙中显示「已连接」，而非仅「已配对」）|
| 与妙控板冲突 | 使用菜单栏中的 **暂停** 选项临时禁用 Siri Remote for macOS |

## 技术说明

- **触摸处理**：使用 Apple 私有框架 `MultitouchSupport.framework` 读取 Siri Remote 触摸板的绝对坐标
- **按钮处理**：使用 `IOKit.hid` 并独占设备（seize），防止 macOS 独立处理遥控器按钮事件
- **媒体键**：通过 `CGEventTap` 拦截系统媒体键，避免 HID 和系统 AVRCP 双路径同时触发
- 因使用私有 API，无法上架 App Store

## 参与贡献

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

MIT 许可证 —— 详见 [LICENSE](LICENSE)。
