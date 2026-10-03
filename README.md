# 业余卫星跟踪与过境预测（HarmonyOS / ArkTS）

**非官方、独立维护的 Look4Sat HarmonyOS / ArkTS 移植版，基于 GPL-3.0 许可。**

这里是 BG5WES。

由于需要接收 SSTV，为了使用 Look4Sat 专门运行虚拟机并不方便，因此开发了这个 HarmonyOS / ArkTS 版本。

## 功能

* 卫星列表与跟踪选择
* 卫星过境预报
* 根据仰角和时间窗口筛选过境
* 雷达图
* 手机朝向准星
* 卫星位置及过境信息查看

## 重要说明

本项目是基于 GPL-3.0 许可的 Look4Sat 项目开发的**非官方 HarmonyOS / ArkTS 移植版**。

本应用不是官方 Look4Sat 发布版本，与官方 Look4Sat 项目不存在隶属关系，也未获得其认可或背书。

HarmonyOS 版本由 BG5WES 独立开发、维护和提供技术支持。有关 HarmonyOS 版本的 Bug、功能建议、发布信息及用户反馈，请通过本项目提供的渠道联系开发者，而不是官方 Look4Sat 项目。

**修改日期：2026-09-28**

## 版权与许可

本项目基于 Look4Sat 项目进行移植和修改。

**Look4Sat**
Copyright (C) 2019-2026 Arty Bishop and contributors.

原始项目：
https://github.com/rt-bishop/Look4Sat

本项目中源自 Look4Sat 的代码及其他相关材料保留原始版权声明。

针对 HarmonyOS / ArkTS 平台独立编写的新增代码及相关内容，其版权归相应作者所有。

本项目按照 **GNU General Public License version 3 or later（GPL-3.0-or-later）** 许可发布。

## 非官方声明

本应用为 Look4Sat 的非官方 HarmonyOS / ArkTS 移植版。

本应用不是官方 Look4Sat 发布版本，与官方 Look4Sat 项目不存在隶属关系，也未获得其认可或背书。

本项目独立开发、维护和发布。HarmonyOS 相关的技术支持、Bug 报告、功能建议及用户反馈请通过本项目渠道提交。

## 问题反馈

HarmonyOS 版本相关问题及功能建议请提交至本项目 GitHub Issues或发送邮件至pengpai.z@qq.com

## 星历更新渠道

### 更新渠道分类（卫星 / 接收器）
  以下更新渠道分类及本项目更新规则，旨在明确数据来源与用户自定义机制，以规避应用上架审核风险。

**说明：**

- “卫星”类用于更新 TLE / OMM（过境预报用的轨道根数），格式含 TLE 三行、3LE、CSV（Celestrak FORMAT=csv）、带 ZIP 压缩的 TLE。
- “接收器”类用于更新转发器/收发信机数据（转发器频率、模式），格式为 JSON（SatNOGS / r4uab / 本项目镜像）。
- 括号里标注了来源与格式，★ 表示本项目（dfh.tys）当前使用/支持的渠道。

---

#### 一、卫星（TLE / OMM）

★ 1. https://tledata.xanyi.eu.org/tledata/all.txt  
     来源：本项目内置镜像（默认渠道）｜格式：TLE 三行｜一次性包含全部卫星  
   2. https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=csv  
     来源：Celestrak｜格式：CSV｜最全的在轨活跃卫星  
   3. https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=tle  
     来源：Celestrak｜格式：TLE 三行  
   4. https://db.satnogs.org/api/tle/?format=3le  
     来源：SatNOGS｜格式：3LE  
   5. https://amsat.org/tle/current/nasabare.txt  
     来源：AMSAT｜格式：TLE（“nasa.bare”精简集，业余卫星为主）  
   6. https://live.ariss.org/iss.txt  
     来源：ARISS｜格式：TLE（仅 ISS 国际空间站）  
   7. https://r4uab.ru/satonline.txt  
     来源：r4uab｜格式：TLE  
   8. https://mmccants.org/tles/classfd.zip  
     来源：McCants｜格式：ZIP 压缩的 TLE（需解压后再解析）  

**提示：** Celestrak 支持按分组取子集，把 `GROUP=active` 换成需要的组即可，例如  
`GROUP=amateur`（业余卫星）、`GROUP=stations`（空间站）、`GROUP=weather`（气象）、  
`GROUP=gnss`（导航）、`GROUP=noaa`（NOAA）、`GROUP=cubesat`（立方星）等；  
CSV/TLE/3LE 由 `FORMAT` 决定（`FORMAT=csv` / `tle` / `3le`）。

---

#### 二、接收器（转发器 / 收发信机）

★ 1. https://tledata.xanyi.eu.org/tledata/trans.json  
     来源：本项目内置镜像（默认渠道）｜格式：JSON 数组  
   2. https://db.satnogs.org/api/transmitters/?format=json&status=active  
     来源：SatNOGS｜格式：JSON（在用的转发器）  
   3. https://r4uab.ru/transmitters.json  
     来源：r4uab｜格式：JSON  

---

#### 三、其它相关接口（不属于“卫星/接收器”数据更新，列出备查）

- https://www.amsat.org/status/api/v1/catalog.php  
  AMSAT 状态目录（卫星“可用性/状态”页）  
- https://www.amsat.org/status/api/v1/reports.php?hours={小时}&limit={条数}  
  读取 AMSAT 状态报告  
- POST https://www.amsat.org/status/api/v1/reports.php  
  提交 AMSAT 状态报告  

---

#### 四、本项目（dfh.tys）的更新规则（现状）

- 默认渠道：只有内置镜像（上面带 ★ 的两条），不再使用 Celestrak 等第三方源；
- 用户自定义：在「设置 → 自定义数据源」填写 URL 后，优先使用该地址，失败再回退内置镜像；地址需以 `http://` 或 `https://` 开头；
- 首次启动：本地无数据时用内置离线快照导入，随后后台静默联网更新；
- 手动更新：设置页「刷新数据」/「保存并更新」，卫星页「下载数据」。

## 致谢

感谢 Arty Bishop 及 Look4Sat contributors 对业余卫星跟踪软件生态的贡献。

73！📡  
循此苦旅，终抵群星

<img width="888" height="628" alt="image" src="https://github.com/user-attachments/assets/66eb61b4-d5a9-4ed8-8321-a42969282d31" />
