# 微雪 1.75C 到货操作卡（Windows + iPhone）

本卡对应当前 iPhone + BLE 圆屏方案；首个实测区域为北京市海淀区。硬件尚未到货，以下是到货后的步骤，不代表已通过实板测试。完整型号只能是 **Waveshare ESP32-S3-Touch-AMOLED-1.75C**。项目预期 ESP32-S3、466×466 的 CO5300 圆屏、CST9217 触控、**32 MB Flash**、8 MB PSRAM；型号、容量或安全状态不符时先停在检查步骤。

## 到货前保留的三个文件

1. 第二阶段 iPhone 包：GitHub [成功构建 #9](https://github.com/liuxd2010skyline-ship-it/moto-gps-waveshare/actions/runs/36751064709) 的 `MotoGPS-checked-unsigned-IPA`；源码 `278495b9322bf9c8cdd3632b0c920cf650869c06`。ZIP SHA-256 为 `b6493ce617a6bac455d5c7931531c3e026a5c01a00c7e2f4d5cbe76c20115d04`，内含原始未签名 IPA SHA-256 为 `06888255d5c3f603668477f0da2cb781f7c72eca409ade9c8d42344e273f97ca`。GitHub 的临时 artifact 会过期，因此本机另存一份。
2. 圆屏固件：[成功构建](https://github.com/liuxd2010skyline-ship-it/moto-gps-waveshare/actions/runs/36812354053) 的 `MotoGPS-ESP32S3-1.75C-5dce4829719d468f5496e60f3268a4eba2e083ec`。GitHub artifact ID 为 `11139857869`，平台保留至 2026-10-31；本机已另存 ZIP。ZIP SHA-256 为 `64a1a206237983e0b88bc9e2457149aea6830a24977b8ed9279ef4e85ee97fcc`。解压后含 `BUILD_INFO.txt`、`SHA256SUMS.txt`、`flasher_args.json`、`flash_project_args`、bootloader、分区表和应用镜像；七个内含文件的摘要已复算通过。只使用同一构建包内的文件与偏移，不能混搭其他版本。
3. 本机备份目录先建好，实际读出的原厂 Flash 备份放在其中，**不上传 GitHub 或发到聊天**；它可能含设备私有内容。保留一份不在下载文件夹中的副本和 SHA-256。

## Windows 准备

- 一根确实支持数据传输的 USB-C 线；先用 USB 供电测试出厂画面。电池、固定件、设备配件按实物核对，不假定购物链接的默认套餐含电池。
- 安装乐鑫官方 **ESP-IDF 5.5.5** Windows 环境；在安装器创建的 IDF 终端中运行以下 `python -m esptool` 命令。`python -m esptool version` 应显示已安装版本。4.x 的子命令使用下划线；5.x 则按 `--help` 改为连字符。固件包由 GitHub 构建，用户无需为了首次刷写再本地编译。
- 打开 Windows 设备管理器的“端口 (COM 和 LPT)”，插拔圆屏以找出新增的 `COM` 号；以下 `COM7` 只是示例，实际命令要替换为自己的端口号。没有串口时先检查数据线、驱动和设备的下载模式。

乐鑫官方说明：[ESP32-S3 v5.5.5 入门](https://docs.espressif.com/projects/esp-idf/en/v5.5.5/esp32s3/get-started/index.html)、[识别串口](https://docs.espressif.com/projects/esp-idf/en/v5.5.5/esp32s3/get-started/establish-serial-connection.html)。

## 先检查，再备份，最后刷写

以下命令在 **IDF 终端**运行，实际端口代替 `COM7`。先运行：

```powershell
python -m esptool version
python -m esptool --chip esp32s3 --port COM7 flash_id
python -m esptool --chip esp32s3 --port COM7 get_security_info
```

确认芯片是 ESP32-S3、Flash 实际容量是 32 MB，并检查安全启动与 Flash 加密状态。若容量、型号、安全状态与预期不符，不执行后续读取和刷写；把这三项的**非私密摘要**记录下来再处理。启用了 Flash 加密的全片备份不等于可恢复的明文固件。

确认设备符合前提后，在一个自己能找回的目录读取原厂完整 32 MB Flash：

```powershell
New-Item -ItemType Directory -Force .\backups | Out-Null
python -m esptool --chip esp32s3 --port COM7 read_flash 0 0x2000000 .\backups\waveshare-original.bin
(Get-Item .\backups\waveshare-original.bin).Length
(Get-FileHash .\backups\waveshare-original.bin -Algorithm SHA256).Hash
```

预期大小为 **33,554,432 字节**。记录 SHA-256，复制备份到另一处私有位置；备份未完成时不刷写。若使用 esptool 5.x，改为 `flash-id`、`get-security-info`、`read-flash`。

解压经过 CI 验证的固件包，先看 `BUILD_INFO.txt` 中的板型、源码提交、IDF 版本和 `SHA256SUMS.txt`。在**包含 `flash_project_args` 的目录**中运行下面命令。该参数文件来自同一固件包，列有本次构建的 bootloader、分区表、应用镜像和偏移；先确认它引用的文件都在解压目录。**此命令会替换原厂固件**：

```powershell
python -m esptool --chip esp32s3 --port COM7 --baud 460800 write_flash '@flash_project_args'
```

以上写法用于随 ESP-IDF 5.5.5 安装的 esptool 4.x；如安装的是 5.x，子命令改为 `write-flash`，并以 `python -m esptool --help` 核实参数。不要先执行 `erase_flash`，也不要把整个第二阶段 IPA 或其他微雪型号的 `.bin` 写入 ESP32。写入失败时先保留备份和错误日志，不反复盲刷。

## 首次静止验收

1. 圆屏启动后应看到 MOTO GPS 开机画面与等待连接状态。手机打开蓝牙、定位和 MOTO GPS App，观察设备连接与断开后的提示。
2. 用已经在 iPhone 上成功测试的百度 AK，在海淀区搜索一个熟悉的目的地，分别预览驾车避高速参考、自行车和电动自行车路线。驾车参考**不是**摩托车专用通行保证。
3. 静止情况下开始短路线，核对圆屏路线、下一动作、距离、方向和剩余信息是否对应手机；测试取消导航和 BLE 重连。缺少真实周边底图时，只能显示路线和导航提示，不能把内置济南样例道路当作海淀地图。
4. 记录屏幕照片、手机与固件版本、是否锁屏、是否断网、观察到的差异。第一次不在骑行过程中操作或判断路线正确性；之后再做安全条件下的实际路口、偏航、弱网、耗电和可读性测试。

当前手机到圆屏的路线/提示与真实道路、建筑、绿地、水体底图是**两条数据链**。前者有手机侧测试与协议实现；后者仍缺一个覆盖海淀区、允许圆屏自绘且符合长期免费条件的正式中国数据源。数据源门槛见 [北京海淀区底图核查](BEIJING_HAIDIAN_MAP_SOURCE_REVIEW.md)。
