# 来源与许可范围

MiniCal 的应用代码、构建脚本及代码生成的图标以 MIT 许可证提供；见 LICENSE。

开发时参考了本地已安装的 TinyCal 1.17.5 的界面、资源结构与行为观察，包含月历标签优先级和系统周数等兼容设计。MiniCal 独立维护，许可证仅覆盖本项目作者有权许可的代码与资源。第三方名称、商标及其他第三方权利不随 MIT 许可证转移。

源码仓库不收录原应用二进制、反编译输出、原应用图标、签名、证书、AppGroup、用户日历或偏好导出。逆向分析的临时资料保留在本地聊天工作目录中。

日历资料的来源与边界：

- 农历换算使用 Foundation 的 Chinese Calendar。
- 节气使用 NOAA 公开的低阶太阳位置模型和 NASA Delta-T 多项式；代码实现属于近似日期计算。参考 [NOAA](https://gml.noaa.gov/grad/solcalc/calcdetails.html) 和 [NASA](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html)。
- 2026 年法定休假与调休数据来自 [国务院办公厅通知](https://www.beijing.gov.cn/zhengce/zhengcefagui/202511/t20251104_4258873.html)。
- 纪念日、传统节日及固定星座日期属于界面观察与日历标签数据；保留来源说明，不作为官方法定假日或精密天文结论。新增或替换数据时需记录可追溯来源和适用许可。

公开发布前，维护者应核对所提交素材及数据的授权范围。系统框架通过系统链接使用，没有重新分发 Apple 的框架文件。
