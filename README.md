# VoyagerSat

业余卫星跟踪与过境预测（HarmonyOS / ArkTS），算法源自 Look4Sat（GPL-3.0）。

## 功能
- 卫星列表与跟踪选择
- 过境预报（仰角 / 时间窗口筛选）
- 雷达图：轨迹、日/月标记、手机朝向准星

## 构建
DevEco Studio 打开本工程 → **File → Project Structure → Signing Configs** 自动签名 → **Build → Build Hap(s)**。

## 数据
首次启动联网下载卫星与转发器数据；之后本地缓存，重启即用。

## 设置
观测站坐标（经纬度/海拔）、最低过境仰角、预测窗口，在「设置」页调整。

## 卸载
长按应用图标 → 卸载。数据保存在应用私有目录，卸载即全部清除。