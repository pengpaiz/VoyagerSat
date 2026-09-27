# VoyagerSat

卫星追踪与过境预报应用（鸿蒙 HarmonyOS 版本）。

## 项目来源

本项目是开源项目 **Look4Sat** 的鸿蒙（HarmonyOS / ArkTS）适配移植版本。

- 原作者：rt-bishop
- 原项目地址：<https://github.com/rt-bishop/Look4Sat>
- 原项目简介：Android 平台的业余无线电卫星追踪与过境预报应用

## 协议声明

本项目基于 **GNU General Public License v3.0（GPL-3.0）** 发布。

根据 GPL-3.0 协议要求，本项目：

- 完整保留原项目版权声明及许可信息（见 `LICENSE` 文件）；
- 对原项目的所有修改均以 GPL-3.0 协议开源；
- 如有分发，须向接收方提供相应的源代码。

请在使用或分发本项目时遵守 GPL-3.0 协议规定。

## 与原项目的差异

- 使用 HarmonyOS ArkTS / ArkUI 重新实现界面与业务逻辑；
- 适配鸿蒙系统 API 与工程结构（`entry` 模块、`module.json5`、路由表等）；
- 核心功能与原项目保持一致：卫星轨道计算、过境预报、TLE 数据导入等。

## 致谢

感谢 Look4Sat 原作者 rt-bishop 及其众多贡献者，以及 Celestrak（<https://celestrak.com>）与 SatNOGS（<https://satnogs.org>）提供的卫星数据支持。